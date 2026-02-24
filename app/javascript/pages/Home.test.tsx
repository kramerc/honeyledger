import { screen } from "@testing-library/dom";
import { describe, expect, it } from "vitest";
import { renderWithProviders } from "../utils/test-utils";
import { Home } from "./Home";

describe("Home", () => {
  it("renders a welcome message", () => {
    renderWithProviders(<Home />);
    expect(screen.getByText(/Welcome to Honeyledger/)).toBeInTheDocument();
  });
});
