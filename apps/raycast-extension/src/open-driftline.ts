import { Toast, showToast } from "@raycast/api";
import { openDriftlineApp } from "./shared";

export default async function Command() {
  const toast = await showToast({
    style: Toast.Style.Animated,
    title: "Opening Driftline",
  });

  try {
    await openDriftlineApp();
    toast.style = Toast.Style.Success;
    toast.title = "Opened Driftline";
  } catch (error) {
    toast.style = Toast.Style.Failure;
    toast.title = "Could not open Driftline";
    toast.message = error instanceof Error ? error.message : "Unknown error";
  }
}
