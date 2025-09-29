# Automated Self-Install Script for an Attendance Tracker Kiosk
import platform
import sys
import os
import subprocess
import time
import venv
import shutil
import pwd
from shutil import which
from typing import Callable

try:
    from rich.console import Console
    from prompt_toolkit import choice
    from prompt_toolkit.formatted_text import HTML
    import requests
except ImportError:
    Console = None
    choice = None
    HTML = None
    requests = None

ENV_PATH: str = os.environ.get("ENV_PATH", "/tmp/attendanceTrackerInstallerEnv")
SKIP_CHECKS: bool = os.environ.get("SKIP_CHECKS", False)

DEPS: list[str] = ["rich~=14.1.0", "prompt-toolkit~=3.0.52", "requests~=2.32.5"]

GH_REPO: str = "meowmeowahr/attendance_tracker_prototype_flutter"

CHECKS: dict[str, Callable[[], bool]] = {
    "Installer is running as root": lambda: is_root(),
    "Available disk space is above 300MB": lambda: get_free_mb() > 300,
    "APT is available": lambda: has_apt()
}


def env_exists(env_dir):
    """Return True if env already exists and looks intact"""
    python_bin = os.path.join(env_dir, "bin", "python")
    pip_bin = os.path.join(env_dir, "bin", "pip")
    return os.path.exists(python_bin) and os.path.exists(pip_bin)


def create_env(env_dir):
    print(f"[*] Creating temporary environment: {env_dir}")
    venv.create(env_dir, with_pip=True)
    python_bin = os.path.join(env_dir, "bin", "python")
    print(f"[*] Installing dependencies: {DEPS}")
    subprocess.check_call([python_bin, "-m", "pip", "install"] + DEPS)
    print("[*] Environment setup complete.")
    return python_bin


def relaunch(env_dir, python_bin):
    print("[*] Relaunching installer inside the temporary environment...")
    os.environ["ENV_PATH"] = env_dir
    os.execv(python_bin, [python_bin] + sys.argv)


def get_default_user():
    """Try to detect default non-root user (UID 1000)"""
    try:
        user_info = pwd.getpwuid(1000)
        return user_info.pw_name
    except KeyError:
        return None


def get_arch():
    arch = platform.machine().lower()
    if arch in ("x86_64", "amd64"):
        return "x86_64"
    elif arch in ("aarch64", "arm64"):
        return "arm64"
    else:
        return None


def get_free_mb(path="/"):
    total, used, free = shutil.disk_usage(path)
    return free // 1024 // 1024


def is_root():
    return os.getuid() == 0

def has_apt():
    return which("apt") is not None and which("apt-get") is not None

def install_countdown(console: Console, seconds: int = 5) -> bool:
    try:
        for remaining in range(seconds, 0, -1):
            console.print(
                f"[dim]Press Ctrl+C to cancel.[/dim] "
                f"Installing in [bold yellow]{remaining}[/]...",
                end="\r",
                highlight=False,
            )
            time.sleep(1)
        return True

    except KeyboardInterrupt:
        console.print("\n[bold red]Cancelled by user (Ctrl+C)[/]")
        return False

def run_installer():
    console = Console()
    console.print("[green]Welcome to the Attendance Tracker Installer![/green]")

    console.print("Running pre-install checks...")

    for name, check in CHECKS.items():
        if check():
            console.print(f"{name}: [green]v[/green]")
        else:
            console.print(f"{name}: [red]x[/red]")
            console.print(
                "[bold red]Installation failed! Check the above logs for more info[/bold red]"
            )
            return 1
    console.print("[bold green]All checks passed![/bold green]")
    console.print(
        "[bold yellow]It is recommended to use the default settings below. Modifying them may result in installation failure, and/or a non-functional kiosk.[/bold yellow]"
    )

    user_account = choice(
        message="Please choose a UNIX user to install to:",
        options=[
            (user.pw_name, user.pw_name)
            for user in pwd.getpwall()
            if user.pw_shell
            not in (
                "/usr/bin/nologin",
                "/usr/sbin/nologin",
                "/sbin/nologin",
                "/bin/nologin",
            )
            and user.pw_uid != 0
        ],
        default=get_default_user(),
    )

    console.print(f"Fetching releases from {GH_REPO}")
    try:
        releases_url = f"https://api.github.com/repos/{GH_REPO}/releases"
        response = requests.get(releases_url, timeout=5)
        releases = response.json()
        valid_releases = []

        for release in releases:
            version = release["tag_name"]
            title = release["name"]
            pre_release = release["prerelease"]
            assets = release["assets"]
            dl_url = None
            for asset in assets:
                if asset["name"] == f"linux-{get_arch()}-{version}.tar.gz":
                    dl_url = asset["browser_download_url"]
            if not dl_url:
                console.print(f"[yellow]Invalid release tag: {version}[/yellow]")

            if dl_url:
                release_info = {
                    "version": version,
                    "title": title,
                    "prerelease": pre_release,
                    "dl_url": dl_url,
                }
                valid_releases.append(release_info)
    except Exception as e:
        console.print(f"[red]Error fetching releases: {repr(e)}[/red]")
        return 1

    release_choice = choice(
        message="Choose your desired Attendance Tracker version:",
        options=[
            (
                rel["version"],
                HTML(
                    f"{'<ansiyellow>' if rel['prerelease'] else ''}"
                    f"{rel['title']} [{rel['version']}]"
                    f"{' [PR]</ansiyellow>' if rel['prerelease'] else ''}"
                )
            )
            for rel in valid_releases
        ],
    )

    # countdown
    ret = install_countdown(console)
    if not ret:
        return 2

    console.print(
        f"[cyan]Installing Attendance Tracker for user: {user_account}[/cyan]"
    )

    console.print("[green]Installation complete.[/green]")
    return 0


if __name__ == "__main__":
    if os.environ.get("INSTALLER_ENV_ACTIVE") != "1":
        if env_exists(ENV_PATH):
            print(f"[*] Using existing environment: {ENV_PATH}")
            python_bin = os.path.join(ENV_PATH, "bin", "python")
        else:
            python_bin = create_env(ENV_PATH)

        os.environ["INSTALLER_ENV_ACTIVE"] = "1"
        relaunch(ENV_PATH, python_bin)
    else:
        sys.exit(run_installer())
