import { Fragment, useRef } from "react";
export function App(){ const ref=useRef(null); return <Fragment ref={ref}><button>Save</button></Fragment>; }
