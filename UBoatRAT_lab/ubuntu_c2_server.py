#!/usr/bin/env python3
"""
Benign UBoatRAT laboratory server.

Provides:

HTTP :8080
    GET/HEAD /health
    GET/HEAD /c2/trigger.dat
    GET/HEAD /resolver/README.md

TCP :9001
    Receives one-shot XOR-encoded benign laboratory beacons.

This server does not:
    - issue commands;
    - provide a shell;
    - accept file uploads;
    - execute received data;
    - implement a remote administration channel.
"""

from __future__ import annotations

import argparse
import base64
import functools
import ipaddress
import re
import socket
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional


XOR_KEY = 0x88

EXPECTED_BEACON = (
    b"488|UBOATRAT_LAB|BENIGN_BEACON|NO_COMMAND_CHANNEL"
)

DEFAULT_HTTP_PORT = 8080
DEFAULT_BEACON_PORT = 9001
DEFAULT_TRIGGER_SIZE_KIB = 256
MAX_BEACON_BYTES = 4096


def utc_timestamp() -> str:
    """Return an ISO-8601 UTC timestamp."""
    return datetime.now(timezone.utc).isoformat()


def is_private_or_loopback_ipv4(value: str) -> bool:
    """Return True only for private or loopback IPv4 addresses."""
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        return False

    return (
        address.version == 4
        and (address.is_private or address.is_loopback)
    )


def validate_private_ipv4(value: str, description: str) -> str:
    """Validate that a value is an RFC1918 or loopback IPv4 address."""
    try:
        address = ipaddress.ip_address(value)
    except ValueError as exc:
        raise ValueError(
            f"{description} is not a valid IP address: {value}"
        ) from exc

    if address.version != 4:
        raise ValueError(f"{description} must be IPv4.")

    if not address.is_private and not address.is_loopback:
        raise ValueError(
            f"{description} must be a private or loopback IPv4 address."
        )

    return str(address)


def detect_private_ipv4(explicit_ip: Optional[str]) -> str:
    """
    Determine the private IPv4 address advertised by the resolver.

    An explicit --advertise-ip value always takes precedence.
    """
    if explicit_ip:
        return validate_private_ipv4(
            explicit_ip,
            "Advertised address",
        )

    # Route-based detection. UDP connect selects an interface but does not
    # establish a real connection or transmit application data.
    try:
        with socket.socket(
            socket.AF_INET,
            socket.SOCK_DGRAM,
        ) as route_socket:
            route_socket.connect(("10.255.255.255", 1))
            candidate = route_socket.getsockname()[0]

            if is_private_or_loopback_ipv4(candidate):
                return candidate
    except OSError:
        pass

    # Hostname-resolution fallback.
    try:
        addresses = socket.getaddrinfo(
            socket.gethostname(),
            None,
            family=socket.AF_INET,
            type=socket.SOCK_STREAM,
        )

        for entry in addresses:
            candidate = entry[4][0]

            if (
                is_private_or_loopback_ipv4(candidate)
                and not ipaddress.ip_address(candidate).is_loopback
            ):
                return candidate
    except OSError:
        pass

    raise RuntimeError(
        "Could not determine the Ubuntu VM private IPv4 address. "
        "Start the server with --advertise-ip <UBUNTU_IP>."
    )


@dataclass
class LabState:
    """Shared configuration and logging state."""

    lab_root: Path
    advertise_ip: str
    bind_address: str
    http_port: int
    beacon_port: int
    trigger_size_kib: int

    stop_event: threading.Event = field(
        default_factory=threading.Event
    )

    log_lock: threading.Lock = field(
        default_factory=threading.Lock
    )

    @property
    def c2_dir(self) -> Path:
        return self.lab_root / "c2"

    @property
    def resolver_dir(self) -> Path:
        return self.lab_root / "resolver"

    @property
    def logs_dir(self) -> Path:
        return self.lab_root / "logs"

    @property
    def trigger_path(self) -> Path:
        return self.c2_dir / "trigger.dat"

    @property
    def resolver_path(self) -> Path:
        return self.resolver_dir / "README.md"

    @property
    def server_log_path(self) -> Path:
        return self.logs_dir / "server.log"

    @property
    def beacon_log_path(self) -> Path:
        return self.logs_dir / "beacon.log"

    def log(
        self,
        message: str,
        *,
        beacon: bool = False,
    ) -> None:
        """Write a timestamped message to stdout and log files."""
        line = f"[{utc_timestamp()}] {message}"

        with self.log_lock:
            print(line, flush=True)

            self.logs_dir.mkdir(
                parents=True,
                exist_ok=True,
            )

            with self.server_log_path.open(
                "a",
                encoding="utf-8",
            ) as server_log:
                server_log.write(line + "\n")

            if beacon:
                with self.beacon_log_path.open(
                    "a",
                    encoding="utf-8",
                ) as beacon_log:
                    beacon_log.write(line + "\n")


def prepare_lab_files(state: LabState) -> None:
    """Create the harmless HTTP resources served by the lab."""
    state.c2_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    state.resolver_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    state.logs_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    endpoint = (
        f"{state.advertise_ip}:{state.beacon_port}"
    )

    encoded_endpoint = base64.b64encode(
        endpoint.encode("ascii")
    ).decode("ascii")

    resolver_content = (
        "# Benign UBoatRAT laboratory resolver\n"
        "# The value below identifies only the private Ubuntu VM.\n"
        f"[Rudeltaktik]{encoded_endpoint}!\n"
    )

    state.resolver_path.write_text(
        resolver_content,
        encoding="utf-8",
    )

    requested_size = state.trigger_size_kib * 1024

    seed = (
        b"BENIGN UBOATRAT LABORATORY BITS TRIGGER\r\n"
    )

    repeats = (requested_size // len(seed)) + 1

    trigger_data = (
        seed * repeats
    )[:requested_size]

    state.trigger_path.write_bytes(trigger_data)

    state.log(
        f"Prepared inert BITS trigger: "
        f"{state.trigger_path} "
        f"({len(trigger_data)} bytes)"
    )

    state.log(
        f"Prepared resolver: {state.resolver_path}"
    )

    state.log(
        f"Resolver decodes to private endpoint: "
        f"{endpoint}"
    )


class LabHttpHandler(BaseHTTPRequestHandler):
    """Restricted HTTP handler exposing only three fixed routes."""

    server_version = "UBoatRATLabHTTP/1.0"
    protocol_version = "HTTP/1.1"

    def __init__(
        self,
        *args,
        state: LabState,
        **kwargs,
    ) -> None:
        self.state = state
        super().__init__(*args, **kwargs)

    def log_message(
        self,
        format_string: str,
        *args,
    ) -> None:
        message = format_string % args

        self.state.log(
            f"HTTP {self.client_address[0]} "
            f"{self.command} {self.path} - {message}"
        )

    def do_GET(self) -> None:
        self._handle_request(send_body=True)

    def do_HEAD(self) -> None:
        self._handle_request(send_body=False)

    def do_POST(self) -> None:
        self.send_error(
            405,
            "POST is not supported by this laboratory server.",
        )

    def do_PUT(self) -> None:
        self.send_error(
            405,
            "PUT is not supported by this laboratory server.",
        )

    def _handle_request(
        self,
        *,
        send_body: bool,
    ) -> None:
        request_path = self.path.split("?", 1)[0]

        if request_path == "/health":
            payload = b"OK\n"

            self._send_bytes(
                payload,
                content_type="text/plain; charset=utf-8",
                send_body=send_body,
                allow_ranges=False,
            )
            return

        if request_path == "/resolver/README.md":
            payload = self.state.resolver_path.read_bytes()

            self._send_bytes(
                payload,
                content_type="text/markdown; charset=utf-8",
                send_body=send_body,
                allow_ranges=False,
            )
            return

        if request_path == "/c2/trigger.dat":
            payload = self.state.trigger_path.read_bytes()

            self._send_bytes(
                payload,
                content_type="application/octet-stream",
                send_body=send_body,
                allow_ranges=True,
            )
            return

        self.send_error(404, "Unknown laboratory resource.")

    def _send_bytes(
        self,
        payload: bytes,
        *,
        content_type: str,
        send_body: bool,
        allow_ranges: bool,
    ) -> None:
        """
        Return bytes with basic Range support.

        Range support improves compatibility with BITS downloads.
        """
        total_length = len(payload)
        status_code = 200
        response_payload = payload
        content_range: Optional[str] = None

        range_header = self.headers.get("Range")

        if allow_ranges and range_header:
            parsed_range = self._parse_range(
                range_header,
                total_length,
            )

            if parsed_range is None:
                self.send_response(416)
                self.send_header(
                    "Content-Range",
                    f"bytes */{total_length}",
                )
                self.send_header("Content-Length", "0")
                self.send_header("Connection", "close")
                self.end_headers()
                return

            start, end = parsed_range

            response_payload = payload[start : end + 1]
            status_code = 206
            content_range = (
                f"bytes {start}-{end}/{total_length}"
            )

        self.send_response(status_code)
        self.send_header("Content-Type", content_type)
        self.send_header(
            "Content-Length",
            str(len(response_payload)),
        )
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")

        if allow_ranges:
            self.send_header("Accept-Ranges", "bytes")

        if content_range:
            self.send_header(
                "Content-Range",
                content_range,
            )

        self.end_headers()

        if send_body:
            self.wfile.write(response_payload)
            self.wfile.flush()

    @staticmethod
    def _parse_range(
        range_header: str,
        total_length: int,
    ) -> Optional[tuple[int, int]]:
        """Parse a single HTTP byte range."""
        match = re.fullmatch(
            r"bytes=(\d*)-(\d*)",
            range_header.strip(),
        )

        if not match:
            return None

        start_text, end_text = match.groups()

        if not start_text and not end_text:
            return None

        try:
            if not start_text:
                suffix_length = int(end_text)

                if suffix_length <= 0:
                    return None

                start = max(
                    total_length - suffix_length,
                    0,
                )
                end = total_length - 1
            else:
                start = int(start_text)

                if start >= total_length:
                    return None

                if end_text:
                    end = min(
                        int(end_text),
                        total_length - 1,
                    )
                else:
                    end = total_length - 1

                if end < start:
                    return None
        except ValueError:
            return None

        return start, end


def read_connection(
    connection: socket.socket,
) -> bytes:
    """Read one bounded beacon and stop at EOF."""
    chunks: list[bytes] = []
    total_bytes = 0

    while total_bytes < MAX_BEACON_BYTES:
        chunk = connection.recv(
            min(
                1024,
                MAX_BEACON_BYTES - total_bytes,
            )
        )

        if not chunk:
            break

        chunks.append(chunk)
        total_bytes += len(chunk)

    return b"".join(chunks)


def decode_beacon(raw_data: bytes) -> bytes:
    """Decode data using the fixed laboratory XOR key."""
    return bytes(
        value ^ XOR_KEY
        for value in raw_data
    )


def beacon_listener(state: LabState) -> None:
    """Listen for fixed, one-shot benign laboratory beacons."""
    listener = socket.socket(
        socket.AF_INET,
        socket.SOCK_STREAM,
    )

    listener.setsockopt(
        socket.SOL_SOCKET,
        socket.SO_REUSEADDR,
        1,
    )

    listener.bind(
        (
            state.bind_address,
            state.beacon_port,
        )
    )

    listener.listen(5)
    listener.settimeout(1.0)

    state.log(
        f"TCP beacon listener active on "
        f"{state.bind_address}:{state.beacon_port}"
    )

    try:
        while not state.stop_event.is_set():
            try:
                connection, client_address = (
                    listener.accept()
                )
            except socket.timeout:
                continue
            except OSError:
                if state.stop_event.is_set():
                    break
                raise

            source_ip, source_port = client_address

            with connection:
                connection.settimeout(5.0)

                if not is_private_or_loopback_ipv4(
                    source_ip
                ):
                    state.log(
                        f"Rejected TCP connection from "
                        f"non-private address "
                        f"{source_ip}:{source_port}",
                        beacon=True,
                    )
                    continue

                state.log(
                    f"Accepted TCP connection from "
                    f"{source_ip}:{source_port}",
                    beacon=True,
                )

                try:
                    raw_data = read_connection(connection)
                except socket.timeout:
                    state.log(
                        "Beacon read timed out.",
                        beacon=True,
                    )
                    continue

                if not raw_data:
                    state.log(
                        "Connection closed without data.",
                        beacon=True,
                    )
                    continue

                decoded_data = decode_beacon(raw_data)

                raw_hex = raw_data.hex(" ").upper()

                decoded_text = decoded_data.decode(
                    "ascii",
                    errors="replace",
                )

                state.log(
                    f"Raw XOR-encoded beacon "
                    f"({len(raw_data)} bytes): "
                    f"{raw_hex}",
                    beacon=True,
                )

                state.log(
                    f"Decoded beacon: {decoded_text}",
                    beacon=True,
                )

                if decoded_data == EXPECTED_BEACON:
                    state.log(
                        "VALID benign UBoatRAT laboratory "
                        "beacon received.",
                        beacon=True,
                    )
                else:
                    state.log(
                        "INVALID or unexpected beacon. "
                        "No response was sent.",
                        beacon=True,
                    )

                # Deliberately send no response.
                # The server cannot issue commands.
    finally:
        listener.close()

        state.log(
            "TCP beacon listener stopped."
        )


def validate_port(value: int, description: str) -> int:
    if not 1 <= value <= 65535:
        raise ValueError(
            f"{description} must be between 1 and 65535."
        )

    return value


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run the benign Ubuntu-side server for the "
            "UBoatRAT behavior-analysis laboratory."
        )
    )

    parser.add_argument(
        "--bind",
        default="0.0.0.0",
        help=(
            "Address on which the HTTP and TCP services bind. "
            "Default: 0.0.0.0"
        ),
    )

    parser.add_argument(
        "--advertise-ip",
        help=(
            "Private Ubuntu IPv4 address encoded in the "
            "dead-drop resolver. Auto-detected when omitted."
        ),
    )

    parser.add_argument(
        "--http-port",
        type=int,
        default=DEFAULT_HTTP_PORT,
        help=f"HTTP port. Default: {DEFAULT_HTTP_PORT}",
    )

    parser.add_argument(
        "--beacon-port",
        type=int,
        default=DEFAULT_BEACON_PORT,
        help=(
            f"TCP beacon port. "
            f"Default: {DEFAULT_BEACON_PORT}"
        ),
    )

    parser.add_argument(
        "--lab-root",
        type=Path,
        default=Path.home() / "BnB" / "UBoatRAT",
        help=(
            "Laboratory root directory. "
            "Default: ~/BnB/UBoatRAT"
        ),
    )

    parser.add_argument(
        "--trigger-size-kib",
        type=int,
        default=DEFAULT_TRIGGER_SIZE_KIB,
        help=(
            "Size of the inert BITS trigger file. "
            f"Default: {DEFAULT_TRIGGER_SIZE_KIB} KiB"
        ),
    )

    return parser.parse_args()


def main() -> int:
    args = parse_arguments()

    try:
        http_port = validate_port(
            args.http_port,
            "HTTP port",
        )

        beacon_port = validate_port(
            args.beacon_port,
            "Beacon port",
        )

        if args.trigger_size_kib < 1:
            raise ValueError(
                "Trigger size must be at least 1 KiB."
            )

        if args.bind != "0.0.0.0":
            validate_private_ipv4(
                args.bind,
                "Bind address",
            )

        advertise_ip = detect_private_ipv4(
            args.advertise_ip
        )
    except (
        ValueError,
        RuntimeError,
    ) as exc:
        print(f"[-] {exc}")
        return 1

    state = LabState(
        lab_root=args.lab_root.expanduser().resolve(),
        advertise_ip=advertise_ip,
        bind_address=args.bind,
        http_port=http_port,
        beacon_port=beacon_port,
        trigger_size_kib=args.trigger_size_kib,
    )

    prepare_lab_files(state)

    handler_factory = functools.partial(
        LabHttpHandler,
        state=state,
    )

    try:
        http_server = ThreadingHTTPServer(
            (
                state.bind_address,
                state.http_port,
            ),
            handler_factory,
        )
    except OSError as exc:
        state.log(
            f"Could not start HTTP server: {exc}"
        )
        return 1

    beacon_thread = threading.Thread(
        target=beacon_listener,
        args=(state,),
        name="UBoatRATLabBeaconListener",
        daemon=True,
    )

    beacon_thread.start()

    state.log(
        "=== Benign UBoatRAT Lab Server ==="
    )

    state.log(
        f"HTTP server: "
        f"http://{state.advertise_ip}:{state.http_port}"
    )

    state.log(
        f"Health check: "
        f"http://{state.advertise_ip}:"
        f"{state.http_port}/health"
    )

    state.log(
        f"BITS trigger: "
        f"http://{state.advertise_ip}:"
        f"{state.http_port}/c2/trigger.dat"
    )

    state.log(
        f"Dead-drop resolver: "
        f"http://{state.advertise_ip}:"
        f"{state.http_port}/resolver/README.md"
    )

    state.log(
        f"TCP listener: "
        f"{state.advertise_ip}:{state.beacon_port}"
    )

    state.log(
        f"Logs: {state.logs_dir}"
    )

    state.log(
        "Press CTRL+C to stop both services."
    )

    try:
        http_server.serve_forever(
            poll_interval=0.5
        )
    except KeyboardInterrupt:
        state.log(
            "Shutdown requested by user."
        )
    finally:
        state.stop_event.set()

        http_server.shutdown()
        http_server.server_close()

        beacon_thread.join(timeout=3.0)

        state.log(
            "UBoatRAT laboratory server stopped."
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
