import { Route, Routes } from "react-router";
import { Home } from "./pages/Home";

export const App = () => {
  return (
    <Routes>
      <Route index element={<Home />} />
    </Routes>
  );
};
