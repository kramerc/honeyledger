import { describe, it, expect, afterEach } from "vitest";
import { makeStore, readPreloadedState } from "./store";

const injectPreloadedState = (content: string) => {
  const script = document.createElement("script");
  script.id = "preloaded-state";
  script.type = "application/json";
  script.textContent = content;
  document.body.appendChild(script);
};

describe("store", () => {
  afterEach(() => {
    document.getElementById("preloaded-state")?.remove();
  });

  it("handles preloaded state", () => {
    injectPreloadedState(
      JSON.stringify({ user: { id: 1, email: "test@example.com" } }),
    );

    const store = makeStore(readPreloadedState());

    expect(store.getState()).toEqual({
      user: { id: 1, email: "test@example.com" },
    });
  });

  it("handles an empty preloaded state tag", () => {
    injectPreloadedState("");

    const store = makeStore(readPreloadedState());

    expect(store.getState()).toEqual({ user: null });
  });

  it("handles a malformed preloaded state", () => {
    injectPreloadedState("not a valid JSON string");

    const store = makeStore(readPreloadedState());

    // The store should fall back to the default slice states instead of throwing an error
    expect(store.getState()).toEqual({ user: null });
  });
});
