// Import legacy Stimulus controllers
import "@hotwired/turbo-rails";
import "../controllers";

// Set up React
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router";
import { Provider } from "react-redux";
import { store } from "../store";
import { App } from "../App";

const rootNode = document.getElementById("app");
if (!rootNode) throw new Error("Failed to find the root element");

const root = createRoot(rootNode);
root.render(
  <Provider store={store}>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </Provider>,
);
