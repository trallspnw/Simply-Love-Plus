#!/usr/bin/env python3
"""
Syncs this machine's ServerSongs/ folder with the stepmania-server song library, then exits.
Run it before starting ITGmania; ITGmania loads ServerSongs/ alongside Songs/.
"""
import argparse
import configparser
import hashlib
import json
import os
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

LOADER_CONFIG_PATH = Path(__file__).with_name("serversongloader.ini")
SERVER_SONGS_FOLDER_NAME = "ServerSongs"
STAGING_FOLDER_NAME = "ServerSongs.staging"
STATE_FILE_RELATIVE_PATH = Path("Save", "ServerSongLoader.json")
SERVER_CONFIG_RELATIVE_PATH = Path("Save", "StepManiaServer.ini")
PREFERENCES_RELATIVE_PATH = Path("Save", "Preferences.ini")
SONG_FOLDERS_PREFERENCE = "AdditionalSongFoldersReadOnly"
MANIFEST_TIMEOUT_SECONDS = 10
DOWNLOAD_TIMEOUT_SECONDS = 60
STATE_SAVE_INTERVAL_SONGS = 25
READ_CHUNK_BYTES = 1 << 20

EXIT_OK = 0
EXIT_SYNC_FAILED = 1
EXIT_SETUP_ERROR = 2


class SetupError(Exception):
    """A problem with this machine's setup that the user has to fix before a sync can run."""


def log(message):
    print(message, flush=True)


def format_size(size_bytes):
    return f"{size_bytes / 1e9:.2f} GB" if size_bytes >= 1e9 else f"{size_bytes / 1e6:.1f} MB"


def read_install_dir(install_dir_argument):
    if install_dir_argument:
        return Path(install_dir_argument).expanduser()

    config = configparser.ConfigParser(interpolation=None)
    config.read(LOADER_CONFIG_PATH, encoding="utf-8")
    install_dir = config.get("ServerSongLoader", "InstallDir", fallback="").strip()
    if not install_dir:
        raise SetupError(
            f"InstallDir is not set. Copy serversongloader.example.ini to {LOADER_CONFIG_PATH.name} "
            "next to this script and set InstallDir, or pass --install-dir."
        )
    return Path(install_dir).expanduser()


def resolve_data_dir(install_dir):
    """ITGmania keeps its data in the install folder when Portable.ini is there, otherwise in ~/.itgmania."""
    if not install_dir.is_dir():
        raise SetupError(f"InstallDir {install_dir} is not a folder.")
    if (install_dir / "Portable.ini").exists():
        return install_dir
    return Path.home() / ".itgmania"


def read_server_config(data_dir):
    config_path = data_dir / SERVER_CONFIG_RELATIVE_PATH
    config = configparser.ConfigParser(interpolation=None)
    config.read(config_path, encoding="utf-8-sig")
    url = config.get("StepManiaServer", "Url", fallback="").strip().rstrip("/")
    token = config.get("StepManiaServer", "Token", fallback="").strip()
    if not url or not token:
        raise SetupError(f"Url and Token must be set in {config_path}.")
    return url, token


def is_itgmania_running():
    for process_folder in Path("/proc").iterdir():
        if not process_folder.name.isdigit():
            continue
        try:
            if (process_folder / "comm").read_text().strip() == "itgmania":
                return True
        except OSError:
            continue
    return False


def write_file_atomically(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_name(path.name + ".tmp")
    temporary_path.write_text(contents, encoding="utf-8", newline="")
    os.replace(temporary_path, path)


def ensure_server_songs_folder_listed(preferences_path, server_songs_dir):
    """Adds ServerSongs/ to the comma-separated song folder preference, keeping any other entries."""
    server_songs_entry = str(server_songs_dir)
    contents = preferences_path.read_text(encoding="utf-8", newline="") if preferences_path.exists() else ""
    # ITGmania writes Preferences.ini with CRLF line endings, even on Linux.
    line_ending = "\n" if contents and "\r\n" not in contents else "\r\n"
    lines = contents.splitlines()

    for index, line in enumerate(lines):
        key, separator, value = line.partition("=")
        if separator and key.strip() == SONG_FOLDERS_PREFERENCE:
            entries = [entry.strip() for entry in value.split(",") if entry.strip()]
            if server_songs_entry in entries:
                return
            lines[index] = f"{SONG_FOLDERS_PREFERENCE}={','.join(entries + [server_songs_entry])}"
            break
    else:
        new_line = f"{SONG_FOLDERS_PREFERENCE}={server_songs_entry}"
        if "[Options]" in lines:
            lines.insert(lines.index("[Options]") + 1, new_line)
        else:
            lines += ["[Options]", new_line]

    write_file_atomically(preferences_path, line_ending.join(lines) + line_ending)
    log(f"Added {server_songs_entry} to {SONG_FOLDERS_PREFERENCE} in {preferences_path}")


def folder_checksum(folder_path, is_recursive):
    """
    sha256 over every file in the folder, in UTF-8 byte order of the `/`-separated relative paths.
    Each file contributes `path NUL size NUL bytes`. Must match stepmania-server's lib/ingestion/folderChecksum.ts.
    """
    files = []
    for directory_path, directory_names, file_names in os.walk(folder_path):
        for file_name in file_names:
            absolute_path = os.path.join(directory_path, file_name)
            relative_path = os.path.relpath(absolute_path, folder_path).replace(os.sep, "/")
            files.append((relative_path, absolute_path))
        if not is_recursive:
            break

    files.sort(key=lambda file: file[0].encode("utf-8"))
    digest = hashlib.sha256()
    for relative_path, absolute_path in files:
        digest.update(f"{relative_path}\0{os.path.getsize(absolute_path)}\0".encode("utf-8"))
        with open(absolute_path, "rb") as file:
            for chunk in iter(lambda: file.read(READ_CHUNK_BYTES), b""):
                digest.update(chunk)
    return digest.hexdigest()


class ServerClient:
    """Machine-token requests to stepmania-server's /api/game/library endpoints."""

    def __init__(self, url, token):
        self.url = url
        self.token = token

    def _open(self, path, timeout_seconds, extra_headers=None):
        headers = {"Authorization": f"Bearer {self.token}", **(extra_headers or {})}
        request = urllib.request.Request(f"{self.url}/api/game/library/{path}", headers=headers)
        return urllib.request.urlopen(request, timeout=timeout_seconds)

    def fetch_manifest(self, etag):
        """Returns (etag, manifest), or (etag, None) when the library is unchanged since `etag`."""
        extra_headers = {"If-None-Match": etag} if etag else None
        try:
            with self._open("manifest", MANIFEST_TIMEOUT_SECONDS, extra_headers) as response:
                return response.headers.get("ETag"), json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 304:
                return etag, None
            raise

    def download(self, path, destination_path):
        with self._open(path, DOWNLOAD_TIMEOUT_SECONDS) as response, open(destination_path, "wb") as file:
            shutil.copyfileobj(response, file, READ_CHUNK_BYTES)
        return destination_path.stat().st_size


def load_state(state_path):
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        state = {}
    return {"etag": state.get("etag"), "packs": state.get("packs", {}), "songs": state.get("songs", {})}


def save_state(state_path, state):
    write_file_atomically(state_path, json.dumps(state, indent=1, sort_keys=True))


def remove_folder_inside(folder_path, root_dir):
    resolved_path = folder_path.resolve()
    if resolved_path.parent != root_dir.resolve() and root_dir.resolve() not in resolved_path.parents:
        raise RuntimeError(f"Refusing to delete {folder_path}: outside {root_dir}")
    shutil.rmtree(resolved_path)


class LibrarySync:
    """One sync run: compares the manifest with saved state and brings ServerSongs/ in line with it."""

    def __init__(self, client, data_dir, should_verify):
        self.client = client
        self.server_songs_dir = data_dir / SERVER_SONGS_FOLDER_NAME
        self.staging_dir = data_dir / STAGING_FOLDER_NAME
        self.state_path = data_dir / STATE_FILE_RELATIVE_PATH
        self.should_verify = should_verify
        self.state = load_state(self.state_path)
        self.failures = []

    def run(self):
        self.server_songs_dir.mkdir(parents=True, exist_ok=True)
        has_missing_folders = any(not (self.server_songs_dir / song_path).is_dir() for song_path in self.state["songs"])
        etag = None if self.should_verify or has_missing_folders else self.state["etag"]

        try:
            new_etag, manifest = self.client.fetch_manifest(etag)
        except urllib.error.HTTPError as error:
            hint = "; check Token in StepManiaServer.ini" if error.code == 401 else ""
            log(f"Server rejected the manifest request (HTTP {error.code}){hint}; keeping the songs already on disk.")
            return False
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            log(f"Server unreachable ({error}); keeping the songs already on disk.")
            return False
        if manifest is None:
            log(f"Up to date: {len(self.state['songs'])} songs.")
            return True

        server_packs = {pack["folder_name"]: pack for pack in manifest["packs"]}
        server_songs = {
            f"{pack['folder_name']}/{song['folder_name']}": song for pack in manifest["packs"] for song in pack["songs"]
        }

        if self.staging_dir.exists():
            shutil.rmtree(self.staging_dir)
        self.staging_dir.mkdir(parents=True)
        try:
            if self.should_verify:
                self._verify_local_folders()
            self._remove_unlisted(server_packs, server_songs)
            self._sync_packs(server_packs)
            self._sync_songs(server_songs)
        finally:
            shutil.rmtree(self.staging_dir, ignore_errors=True)

        self.state["etag"] = None if self.failures else new_etag
        save_state(self.state_path, self.state)
        log(f"Sync finished: {len(self.state['songs'])} songs, {len(self.failures)} failed.")
        for failure in self.failures:
            log(f"  failed: {failure}")
        return not self.failures

    def _verify_local_folders(self):
        log("Verifying local folders against saved checksums...")
        for pack_folder_name in list(self.state["packs"]):
            pack_dir = self.server_songs_dir / pack_folder_name
            if not pack_dir.is_dir() or folder_checksum(pack_dir, is_recursive=False) != self.state["packs"][pack_folder_name]:
                del self.state["packs"][pack_folder_name]
        for song_path in list(self.state["songs"]):
            song_dir = self.server_songs_dir / song_path
            if not song_dir.is_dir() or folder_checksum(song_dir, is_recursive=True) != self.state["songs"][song_path]:
                log(f"  changed locally: {song_path}")
                del self.state["songs"][song_path]

    def _remove_unlisted(self, server_packs, server_songs):
        """Deletes packs and songs that are on disk but no longer on the server."""
        for pack_dir in sorted(self.server_songs_dir.iterdir()):
            if not pack_dir.is_dir():
                continue
            if pack_dir.name not in server_packs:
                log(f"Removing pack {pack_dir.name}")
                remove_folder_inside(pack_dir, self.server_songs_dir)
                continue
            for song_dir in sorted(pack_dir.iterdir()):
                if song_dir.is_dir() and f"{pack_dir.name}/{song_dir.name}" not in server_songs:
                    log(f"Removing song {pack_dir.name}/{song_dir.name}")
                    remove_folder_inside(song_dir, self.server_songs_dir)

        self.state["packs"] = {name: checksum for name, checksum in self.state["packs"].items() if name in server_packs}
        self.state["songs"] = {path: checksum for path, checksum in self.state["songs"].items() if path in server_songs}

    def _download_and_extract(self, archive_path, name):
        """Downloads one archive into staging and extracts it to a fresh folder; returns that folder."""
        zip_path = self.staging_dir / f"{name}.zip"
        size_bytes = self.client.download(archive_path, zip_path)
        extracted_dir = self.staging_dir / name
        with zipfile.ZipFile(zip_path) as archive:
            archive.extractall(extracted_dir)
        zip_path.unlink()
        return extracted_dir, size_bytes

    def _sync_packs(self, server_packs):
        """Pack-root files (pack.ini, pack banner) are replaced file by file, since song folders share the pack folder."""
        for pack_folder_name, pack in server_packs.items():
            if pack["checksum"] is None or self.state["packs"].get(pack_folder_name) == pack["checksum"]:
                continue
            try:
                extracted_dir, _ = self._download_and_extract(f"packs/{pack['id']}/archive", f"pack-{pack['id']}")
                if folder_checksum(extracted_dir, is_recursive=False) != pack["checksum"]:
                    raise RuntimeError("checksum mismatch; re-run ingestion on the server")

                pack_dir = self.server_songs_dir / pack_folder_name
                pack_dir.mkdir(exist_ok=True)
                new_file_names = {path.name for path in extracted_dir.iterdir() if path.is_file()}
                for old_file in pack_dir.iterdir():
                    if old_file.is_file() and old_file.name not in new_file_names:
                        old_file.unlink()
                for file_name in new_file_names:
                    os.replace(extracted_dir / file_name, pack_dir / file_name)
                shutil.rmtree(extracted_dir)

                self.state["packs"][pack_folder_name] = pack["checksum"]
                log(f"Pack files updated: {pack_folder_name}")
            except Exception as error:
                self.failures.append(f"pack {pack_folder_name}: {error}")

    def _sync_songs(self, server_songs):
        changed_song_paths = sorted(
            song_path
            for song_path, song in server_songs.items()
            if self.state["songs"].get(song_path) != song["checksum"] or not (self.server_songs_dir / song_path).is_dir()
        )
        started_at = time.monotonic()
        downloaded_bytes = 0

        for position, song_path in enumerate(changed_song_paths, start=1):
            song = server_songs[song_path]
            try:
                extracted_dir, size_bytes = self._download_and_extract(f"songs/{song['id']}/archive", f"song-{song['id']}")
                downloaded_bytes += size_bytes
                if folder_checksum(extracted_dir, is_recursive=True) != song["checksum"]:
                    shutil.rmtree(extracted_dir)
                    raise RuntimeError("checksum mismatch; re-run ingestion on the server")
                self._swap_into_place(extracted_dir, self.server_songs_dir / song_path)
                self.state["songs"][song_path] = song["checksum"]
                log(f"[{position}/{len(changed_song_paths)}] {song_path} ({format_size(size_bytes)})")
            except Exception as error:
                self.failures.append(f"song {song_path}: {error}")
                log(f"[{position}/{len(changed_song_paths)}] FAILED {song_path}: {error}")

            if position % STATE_SAVE_INTERVAL_SONGS == 0:
                save_state(self.state_path, self.state)

        if changed_song_paths:
            elapsed_seconds = time.monotonic() - started_at
            log(f"Downloaded {format_size(downloaded_bytes)} in {elapsed_seconds / 60:.1f} minutes.")

    def _swap_into_place(self, extracted_dir, song_dir):
        """Renames the verified copy into place, so ITGmania never sees a half-written song."""
        song_dir.parent.mkdir(parents=True, exist_ok=True)
        if song_dir.exists():
            replaced_dir = Path(tempfile.mkdtemp(prefix="replaced-", dir=self.staging_dir))
            os.replace(song_dir, replaced_dir / "song")
            os.replace(extracted_dir, song_dir)
            shutil.rmtree(replaced_dir)
        else:
            os.replace(extracted_dir, song_dir)


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Sync ServerSongs/ with the stepmania-server song library. Run before starting ITGmania."
    )
    parser.add_argument("--install-dir", help="ITGmania install folder; overrides InstallDir in serversongloader.ini")
    parser.add_argument(
        "--verify",
        action="store_true",
        help="rehash every local server song and re-download any that changed or went missing",
    )
    return parser.parse_args()


def main():
    arguments = parse_arguments()
    try:
        install_dir = read_install_dir(arguments.install_dir)
        data_dir = resolve_data_dir(install_dir)
        url, token = read_server_config(data_dir)
        if is_itgmania_running():
            raise SetupError("ITGmania is running. Quit it first: it rewrites Preferences.ini on exit.")
        ensure_server_songs_folder_listed(data_dir / PREFERENCES_RELATIVE_PATH, data_dir / SERVER_SONGS_FOLDER_NAME)
    except SetupError as error:
        log(f"serversongloader: {error}")
        return EXIT_SETUP_ERROR

    log(f"Syncing {data_dir / SERVER_SONGS_FOLDER_NAME} from {url}")
    is_success = LibrarySync(ServerClient(url, token), data_dir, arguments.verify).run()
    return EXIT_OK if is_success else EXIT_SYNC_FAILED


if __name__ == "__main__":
    sys.exit(main())
