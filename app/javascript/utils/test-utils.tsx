import React, { type PropsWithChildren } from "react";
import type { RenderOptions } from "@testing-library/react";
import { render } from "@testing-library/react";
import { userEvent, type Options } from "@testing-library/user-event";
import { Provider } from "react-redux";
import type { AppStore, RootState } from "../store";
import { makeStore } from "../store";

// This type interface extends the default options for render from RTL, as well
// as allows the user to specify other things such as preloadedState, store.
interface ExtendedRenderOptions extends Omit<
  RenderOptions,
  "queries" | "wrapper"
> {
  preloadedState?: Partial<RootState>;
  store?: AppStore;
  userEventOptions?: Options;
}

export function renderWithProviders(
  ui: React.ReactElement,
  extendedRenderOptions: ExtendedRenderOptions = {},
) {
  const {
    preloadedState = {},
    // Automatically create a store instance if no store was passed in
    store = makeStore(preloadedState),
    userEventOptions,
    ...renderOptions
  } = extendedRenderOptions;

  const Wrapper = ({ children }: PropsWithChildren) => (
    <Provider store={store}>{children}</Provider>
  );

  // Return an object with the store, user, and all of RTL's query functions
  return {
    store,
    user: userEvent.setup(userEventOptions),
    ...render(ui, { wrapper: Wrapper, ...renderOptions }),
  };
}
