import { createAppSlice } from "../../createAppSlice";

export type UserSliceState = {
  id: number;
  email: string;
};

export const userSlice = createAppSlice({
  name: "user",
  initialState: null as UserSliceState | null,
  reducers: (create) => ({
    setUser: create.reducer(
      (state, action: { payload: UserSliceState }) => action.payload,
    ),
    clearUser: create.reducer(() => null),
  }),
  selectors: {
    selectUser: (state) => state,
  },
});

export const { setUser, clearUser } = userSlice.actions;
export const { selectUser } = userSlice.selectors;
