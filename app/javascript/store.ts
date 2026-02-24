import {
  combineSlices,
  configureStore,
  type Action,
  type ThunkAction,
} from "@reduxjs/toolkit";
import { setupListeners } from "@reduxjs/toolkit/query";
import { userSlice } from "./features/user/userSlice";

const rootReducer = combineSlices(userSlice);
export type RootState = ReturnType<typeof rootReducer>;

export const makeStore = (preloadedState?: Partial<RootState>) => {
  const store = configureStore({
    reducer: rootReducer,
    preloadedState,
  });
  setupListeners(store.dispatch);
  return store;
};

// Reads and parses the preloaded state injected by the server, if available.
// Returns an empty object if the tag is missing or the JSON is malformed.
export const readPreloadedState = (): Partial<RootState> => {
  const tag = document.getElementById("preloaded-state");
  if (!tag) return {};
  try {
    return JSON.parse(tag.textContent || "{}");
  } catch {
    return {};
  }
};

export const store = makeStore(readPreloadedState());

export type AppStore = typeof store;
export type AppDispatch = AppStore["dispatch"];
export type AppThunk<ThunkReturnType = void> = ThunkAction<
  ThunkReturnType,
  RootState,
  unknown,
  Action
>;
