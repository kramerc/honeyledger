import { application } from "./application";
import { registerControllers } from "stimulus-vite-helpers";

export const controllers = import.meta.glob("../**/*_controller.ts", {
  eager: true,
});
registerControllers(application, controllers);
