// Import legacy Stimulus controllers
import "@hotwired/turbo-rails";
import "../controllers";

// Set up React
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router";
import { App } from "../App";

const rootNode = document.getElementById("app");
if (!rootNode) throw new Error("Failed to find the root element");

const root = createRoot(rootNode);
root.render(
  <BrowserRouter>
    <App />
  </BrowserRouter>,
);
