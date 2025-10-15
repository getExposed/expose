import {type JSX} from "react";
import {NavLink, useSearchParams} from "react-router-dom";
import {RocketIcon} from "@radix-ui/react-icons";

export function NotFound(): JSX.Element {
    const [searchParams] = useSearchParams();
    const tunnelID = searchParams.get("tunnelID") as string;

    return (
        <div className="text-center">
            <h1 className="text-5xl font-bold tracking-tight text-zinc-900">
                Tunnel Not Found!
            </h1>
            <div className="inline-flex items-center justify-center">
                <p className="mt-6 text-lg leading-8 text-gray-600">
                    Tunnel with ID
                    <span className="leading-sm mx-2 inline-flex items-center rounded-full border bg-white px-3 py-2 text-xs font-bold text-gray-700">
                        <RocketIcon className="mr-2" />
                        {tunnelID}
                    </span>
                    not found.
                </p>
            </div>
            <div className="mt-10 flex items-center justify-center gap-x-6">
                <NavLink to="/">
                    <span className="rounded-md bg-blue-600 px-3.5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-blue-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-500">
                        Go back
                    </span>
                </NavLink>
                <a
                    href="https://dl.getexposed.io/"
                    className="text-sm font-semibold leading-6 text-gray-900"
                >
                    Show docs →
                </a>
            </div>
        </div>
    );
}