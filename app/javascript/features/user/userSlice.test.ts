import { beforeEach, describe, expect, it } from "vitest";
import { selectUser, userSlice, type UserSliceState } from "./userSlice";
import { makeStore } from "../../store";

describe("user reducer", () => {
  const initialState: UserSliceState = {
    id: 1,
    email: "test@example.com",
  };

  let store = makeStore();

  beforeEach(() => {
    store = makeStore({ user: initialState });
  });

  it("should handle initial state", async () => {
    expect(userSlice.reducer(undefined, { type: "unknown" })).toStrictEqual(
      null,
    );
  });

  it("should handle setUser", () => {
    expect(selectUser(store.getState())).toStrictEqual(initialState);

    const newUser: UserSliceState = {
      id: 2,
      email: "new@example.com",
    };
    store.dispatch(userSlice.actions.setUser(newUser));

    expect(selectUser(store.getState())).toStrictEqual(newUser);
  });

  it("should handle clearUser", () => {
    expect(selectUser(store.getState())).toStrictEqual(initialState);

    store.dispatch(userSlice.actions.clearUser());

    expect(selectUser(store.getState())).toStrictEqual(null);
  });
});
