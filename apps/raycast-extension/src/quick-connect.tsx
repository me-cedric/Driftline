import { Action, ActionPanel, Form, Toast, showToast } from "@raycast/api";
import {
  defaultPort,
  normalizeConnectionInput,
  openConnection,
  saveRecentConnection,
} from "./shared";

type QuickConnectValues = {
  protocol: string;
  host: string;
  port: string;
  username: string;
  path?: string;
};

export default function Command() {
  async function handleSubmit(values: QuickConnectValues) {
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Opening connection",
    });

    try {
      const connection = normalizeConnectionInput(values);
      await saveRecentConnection(connection);
      const result = await openConnection(connection);

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

  return (
    <Form
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Open Connection" onSubmit={handleSubmit} />
        </ActionPanel>
      }
    >
      <Form.Dropdown
        id="protocol"
        title="Protocol"
        defaultValue="sftp"
        storeValue
      >
        <Form.Dropdown.Item value="sftp" title="SFTP" />
        <Form.Dropdown.Item value="ftp" title="FTP" />
        <Form.Dropdown.Item value="ftps" title="FTPS" />
      </Form.Dropdown>
      <Form.TextField id="host" title="Host" placeholder="example.com" />
      <Form.TextField
        id="port"
        title="Port"
        defaultValue={defaultPort("sftp")}
      />
      <Form.TextField id="username" title="Username" placeholder="user" />
      <Form.TextField id="path" title="Path" placeholder="/optional/path" />
    </Form>
  );
}
