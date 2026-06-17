import { Action, ActionPanel, List, Toast, showToast } from "@raycast/api";
import { useEffect, useState } from "react";
import {
  RecentConnection,
  formatConnection,
  loadRecentConnections,
  openConnection,
  openDriftlineApp,
  protocolTitle,
  removeRecentConnection,
  saveRecentConnection,
} from "./shared";

export default function Command() {
  const [connections, setConnections] = useState<RecentConnection[]>();

  useEffect(() => {
    loadRecentConnections().then(setConnections);
  }, []);

  async function handleOpen(connection: RecentConnection) {
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Opening connection",
    });

    try {
      await saveRecentConnection(connection);
      const result = await openConnection(connection);
      setConnections(await loadRecentConnections());

      toast.style = Toast.Style.Success;
      toast.title = result.usedFallback
        ? "Opened Driftline"
        : "Opened connection";
      toast.message = result.usedFallback
        ? "Connect URL copied until deep links are native."
        : undefined;
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Connection not opened";
      toast.message = error instanceof Error ? error.message : "Unknown error";
    }
  }

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

  async function handleRemove(connection: RecentConnection) {
    await removeRecentConnection(connection.id);
    setConnections(await loadRecentConnections());
  }

  return (
    <List
      isLoading={!connections}
      searchBarPlaceholder="Search recent connections"
    >
      {connections?.length === 0 ? (
        <List.EmptyView
          title="No Recent Connections"
          description="Use Quick Connect to add a recent connection."
          actions={
            <ActionPanel>
              <Action title="Open Driftline" onAction={handleOpenApp} />
            </ActionPanel>
          }
        />
      ) : (
        connections?.map((connection) => (
          <List.Item
            key={connection.id}
            title={formatConnection(connection)}
            subtitle={protocolTitle(connection.protocol)}
            accessories={[
              { text: new Date(connection.lastOpenedAt).toLocaleDateString() },
            ]}
            actions={
              <ActionPanel>
                <Action
                  title="Open Connection"
                  onAction={() => handleOpen(connection)}
                />
                <Action.CopyToClipboard
                  title="Copy Host"
                  content={connection.host}
                />
                <Action title="Open Driftline" onAction={handleOpenApp} />
                <Action
                  title="Remove Recent Connection"
                  style={Action.Style.Destructive}
                  onAction={() => handleRemove(connection)}
                />
              </ActionPanel>
            }
          />
        ))
      )}
    </List>
  );
}
