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

// Hydrate the store with preloaded state from the server, if available
const preloadedStateTag = document.getElementById("preloaded-state");
const preloadedState: RootState = preloadedStateTag
  ? JSON.parse(preloadedStateTag.textContent || "{}")
  : {};

export const store = makeStore(preloadedState);

export type AppStore = typeof store;
export type AppDispatch = AppStore["dispatch"];
export type AppThunk<ThunkReturnType = void> = ThunkAction<
  ThunkReturnType,
  RootState,
  unknown,
  Action
>;
