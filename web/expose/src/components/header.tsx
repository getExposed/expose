import {type JSX} from "react";
import {NavLink} from "react-router-dom";
import { GitHubLogoIcon } from "@radix-ui/react-icons";

export function Header(): JSX.Element {
    return (
        <header className="absolute inset-x-0 top-0 z-50">
            <nav className="mx-auto flex max-w-4xl items-center justify-between p-4">
                <div className="flex flex-1">
                    <NavLink to="/">
                        <img className="h-8" src="/vite.svg" alt="Bore" />
                    </NavLink>
                </div>
                <div className="flex items-center justify-end">
                    <a
                        href="https://github.com/getExposed/expose"
                        className="text-green-600 transition-colors hover:text-green-500"
                    >
                        <GitHubLogoIcon className="h-6 w-6" />
                    </a>
                </div>
            </nav>
        </header>
    );
}