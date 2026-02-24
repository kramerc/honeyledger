import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router";
import { Provider } from "react-redux";
import { store } from "./store";
import { App } from "./App";

export const main = () => {
  const rootNode = document.getElementById("app");
  if (!rootNode) throw new Error("Failed to find the root element");

  createRoot(rootNode).render(
    <Provider store={store}>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </Provider>,
  );
};
