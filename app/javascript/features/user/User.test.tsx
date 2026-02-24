import { screen } from "@testing-library/dom";
import { describe, expect, it } from "vitest";
import { renderWithProviders } from "../../utils/test-utils";
import type { UserSliceState } from "./userSlice";
import { User } from "./User";

describe("User", () => {
  const initialState: UserSliceState = {
    id: 1,
    email: "test@example.com",
  };

  it("renders user information when user is logged in", () => {
    renderWithProviders(<User />, { preloadedState: { user: initialState } });

    expect(screen.getByText(/ID: 1/)).toBeInTheDocument();
    expect(screen.getByText(/Email: test@example.com/)).toBeInTheDocument();
  });

  it("renders a message when no user is logged in", () => {
    renderWithProviders(<User />);

    expect(screen.getByText(/No user logged in/)).toBeInTheDocument();
  });
});
