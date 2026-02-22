const pageIdentifierToPageComponent: Record<string, any> = {};

const pages = import.meta.glob("../views/**/*.tsx", { eager: true });

for (const key in pages) {
  if (pages.hasOwnProperty(key)) {
    const identifier = key.replace("../views/", "").split(".")[0];
    pageIdentifierToPageComponent[identifier] = (pages[key] as any).default;
  }
}

export { pageIdentifierToPageComponent };
