import {
  Clipboard,
  LocalStorage,
  getApplications,
  getPreferenceValues,
  open,
} from "@raycast/api";
import type { Application } from "@raycast/api";
import { URL } from "node:url";

export const DEFAULT_BUNDLE_ID = "app.driftline.Driftline";
export const PROTOCOLS = ["sftp", "ftp", "ftps"] as const;
export type ConnectionProtocol = (typeof PROTOCOLS)[number];

export type ConnectionInput = {
  protocol: ConnectionProtocol;
  host: string;
  port: number;
  username: string;
  path?: string;
};

export type RecentConnection = ConnectionInput & {
  id: string;
  lastOpenedAt: string;
};

type Preferences = {
  bundleId?: string;
};

type RawConnectionInput = {
  protocol: string;
  host: string;
  port: string;
  username: string;
  path?: string;
};

const RECENTS_KEY = "recent-connections-v1";
const MAX_RECENT_CONNECTIONS = 8;

export function getConfiguredBundleId(): string {
  const preferences = getPreferenceValues<Preferences>();
  return preferences.bundleId?.trim() || DEFAULT_BUNDLE_ID;
}

export async function findDriftlineApplication(): Promise<
  Application | undefined
> {
  const bundleId = getConfiguredBundleId();
  const applications = await getApplications();
  return (
    applications.find((application) => application.bundleId === bundleId) ??
    applications.find((application) => application.name === "Driftline")
  );
}

export async function openDriftlineApp(): Promise<void> {
  const application = await findDriftlineApplication();
  if (!application?.path) {
    throw new Error(
      `Driftline not found. Check bundle id ${getConfiguredBundleId()}.`,
    );
  }

  await open(application.path);
}

export function normalizeConnectionInput(
  values: RawConnectionInput,
): ConnectionInput {
  const protocol = values.protocol.trim().toLowerCase();
  if (!isConnectionProtocol(protocol)) {
    throw new Error("Protocol must be SFTP, FTP, or FTPS.");
  }

  const host = values.host.trim();
  if (!host) {
    throw new Error("Host is required.");
  }
  if (/^\w+:\/\//.test(host) || /[\s/?#]/.test(host)) {
    throw new Error(
      "Host must be a hostname or IP address, without protocol or path.",
    );
  }

  const username = values.username.trim();
  if (!username) {
    throw new Error("Username is required.");
  }

  const portText = values.port.trim();
  if (!/^\d+$/.test(portText)) {
    throw new Error("Port must be a number.");
  }

  const port = Number(portText);
  if (!Number.isSafeInteger(port) || port < 1 || port > 65535) {
    throw new Error("Port must be between 1 and 65535.");
  }

  const path = values.path?.trim();
  if (path && !path.startsWith("/")) {
    throw new Error("Path must start with /.");
  }

  return {
    protocol,
    host,
    port,
    username,
    ...(path ? { path } : {}),
  };
}

export function buildConnectionURL(connection: ConnectionInput): string {
  const url = new URL("driftline://connect");
  url.searchParams.set("protocol", connection.protocol);
  url.searchParams.set("host", connection.host);
  url.searchParams.set("port", String(connection.port));
  url.searchParams.set("username", connection.username);

  if (connection.path) {
    url.searchParams.set("path", connection.path);
  }

  return url.toString();
}

export async function openConnection(connection: ConnectionInput): Promise<{
  url: string;
  usedFallback: boolean;
}> {
  const url = buildConnectionURL(connection);

  try {
    await open(url);
    return { url, usedFallback: false };
  } catch {
    await Clipboard.copy(url);
    await openDriftlineApp();
    return { url, usedFallback: true };
  }
}

export async function loadRecentConnections(): Promise<RecentConnection[]> {
  const rawValue = await LocalStorage.getItem<string>(RECENTS_KEY);
  if (!rawValue) {
    return [];
  }

  try {
    const parsed = JSON.parse(rawValue) as RecentConnection[];
    return parsed.filter(isRecentConnection);
  } catch {
    return [];
  }
}

export async function saveRecentConnection(
  connection: ConnectionInput,
): Promise<void> {
  const existing = await loadRecentConnections();
  const id = connectionId(connection);
  const next: RecentConnection[] = [
    {
      ...connection,
      id,
      lastOpenedAt: new Date().toISOString(),
    },
    ...existing.filter((recent) => recent.id !== id),
  ].slice(0, MAX_RECENT_CONNECTIONS);

  await LocalStorage.setItem(RECENTS_KEY, JSON.stringify(next));
}

export async function removeRecentConnection(id: string): Promise<void> {
  const existing = await loadRecentConnections();
  await LocalStorage.setItem(
    RECENTS_KEY,
    JSON.stringify(existing.filter((recent) => recent.id !== id)),
  );
}

export function protocolTitle(protocol: ConnectionProtocol): string {
  return protocol.toUpperCase();
}

export function defaultPort(protocol: ConnectionProtocol): string {
  switch (protocol) {
    case "ftp":
      return "21";
    case "ftps":
      return "990";
    case "sftp":
      return "22";
  }
}

export function formatConnection(connection: ConnectionInput): string {
  const path = connection.path ? connection.path : "";
  return `${connection.username}@${connection.host}:${connection.port}${path}`;
}

function isConnectionProtocol(
  protocol: string,
): protocol is ConnectionProtocol {
  return PROTOCOLS.includes(protocol as ConnectionProtocol);
}

function connectionId(connection: ConnectionInput): string {
  return encodeURIComponent(
    [
      connection.protocol,
      connection.host.toLowerCase(),
      String(connection.port),
      connection.username,
      connection.path ?? "",
    ].join("\u001f"),
  );
}

function isRecentConnection(value: unknown): value is RecentConnection {
  if (!value || typeof value !== "object") {
    return false;
  }

  const candidate = value as Partial<RecentConnection>;
  return (
    typeof candidate.id === "string" &&
    typeof candidate.host === "string" &&
    typeof candidate.port === "number" &&
    typeof candidate.username === "string" &&
    typeof candidate.lastOpenedAt === "string" &&
    typeof candidate.protocol === "string" &&
    isConnectionProtocol(candidate.protocol) &&
    (candidate.path === undefined || typeof candidate.path === "string")
  );
}
