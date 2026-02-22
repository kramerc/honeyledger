import React, { useContext } from "react";
import { NavigationContext } from "@thoughtbot/superglue";

type LinkProps = {
  path: string;
  children: React.ReactNode;
};

export const Link = ({ path, children }: LinkProps) => {
  const { navigateTo } = useContext(NavigationContext);

  const handleClick = (event: React.MouseEvent<HTMLAnchorElement>) => {
    event.preventDefault();
    navigateTo(path, { action: "push" });
  };

  return (
    <a href={path} onClick={handleClick}>
      {children}
    </a>
  );
};
