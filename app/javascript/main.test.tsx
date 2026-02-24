import { describe, it, expect, afterEach, beforeEach } from "vitest";
import { act } from "react";
import { main } from "./main";

// Set up React testing environment
declare global {
  var IS_REACT_ACT_ENVIRONMENT: boolean | undefined;
}
globalThis.IS_REACT_ACT_ENVIRONMENT = true;

describe("main", () => {
  let appDiv: HTMLDivElement;

  beforeEach(() => {
    appDiv = document.createElement("div");
    appDiv.id = "app";
    document.body.appendChild(appDiv);
  });

  afterEach(() => {
    appDiv.remove();
  });

  it("mounts the React app into #app", async () => {
    window.history.pushState({}, "", "/");
    await act(async () => {
      main();
    });
    expect(appDiv.innerHTML).not.toBe("");
  });

  it("throws when #app is missing", () => {
    appDiv.remove();
    expect(() => main()).toThrow("Failed to find the root element");
  });
});
