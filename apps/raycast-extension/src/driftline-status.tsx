import { MenuBarExtra, Toast, showToast } from "@raycast/api";
import { useEffect, useState } from "react";
import {
  RecentConnection,
  findDriftlineApplication,
  formatConnection,
  loadRecentConnections,
  openConnection,
  openDriftlineApp,
} from "./shared";

type StatusState = {
  appInstalled: boolean;
  recentConnections: RecentConnection[];
};

export default function Command() {
  const [status, setStatus] = useState<StatusState>();

  useEffect(() => {
    Promise.all([findDriftlineApplication(), loadRecentConnections()]).then(
      ([application, recentConnections]) => {
        setStatus({
          appInstalled: Boolean(application),
          recentConnections,
        });
      },
    );
  }, []);

  async function handleOpenApp() {
    try {
      await openDriftlineApp();
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Could not open Driftline",
        message: error instanceof Error ? error.message : "Unknown error",
      });
    }
  }

  async function handleOpenConnection(connection: RecentConnection) {
    try {
      await openConnection(connection);
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Connection not opened",
        message: error instanceof Error ? error.message : "Unknown error",
      });
    }
  }

  const installed = status?.appInstalled ?? false;
  const title = installed ? "Driftline Idle" : "Driftline Missing";
  const firstRecent = status?.recentConnections[0];

  return (
    <MenuBarExtra title={title} icon="icon.png" isLoading={!status}>
      <MenuBarExtra.Section>
        <MenuBarExtra.Item
          title="App"
          subtitle={installed ? "Installed" : "Not Found"}
        />
        <MenuBarExtra.Item title="Transfers" subtitle="Idle" />
      </MenuBarExtra.Section>
      <MenuBarExtra.Section title="Actions">
        <MenuBarExtra.Item title="Open Driftline" onAction={handleOpenApp} />
        {firstRecent ? (
          <MenuBarExtra.Item
            title="Open Recent"
            subtitle={formatConnection(firstRecent)}
            onAction={() => handleOpenConnection(firstRecent)}
          />
        ) : null}
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
