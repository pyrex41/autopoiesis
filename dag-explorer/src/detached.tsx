/* @refresh reload */
import { render } from "solid-js/web";
import DetachedApp from "./DetachedApp";
import "./styles/global.css";

render(() => <DetachedApp />, document.getElementById("root")!);
