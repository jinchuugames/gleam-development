# Frontend (Lustre)

Load this when the project has a browser UI built with Lustre: choosing where
state lives, handling pointer interactions, animation, or embedding a Gleam
component in an existing page.

Verified here against `lustre 5.7.1` on `gleam 1.19.2`, Erlang target and
JavaScript target: every signature quoted below was read from the pinned source
and the state-machine test at the end was compiled and run on both targets.
Anything marked **opinion** is a judgement, not a measurement.

## Server component or client island

Lustre has two mechanisms, and the choice is about where the state and the
latency live.

| | Server component | Client island |
| --- | --- | --- |
| Entry | `lustre.start_server_component(app, args)` | `lustre.start(app, onto: selector, with: args)` |
| State lives | in a BEAM process | in the browser |
| Transport | DOM patches over a WebSocket | none |
| Markup | `server_component.element(attributes, children)` plus `server_component.script()` | the island replaces its container |
| Client to server | `server_component.emit(event, json)` from an effect | not applicable |
| Needs | an Erlang host, a live connection | a JavaScript bundle |

Verified surface: `server_component.route(path)`, `server_component.method(WebSocket)`
(`TransportMethod` is `WebSocket | ServerSentEvents | Polling`),
`server_component.csrf_token(token)`, `server_component.include(event, properties)`,
`server_component.select(selector)`, and `lustre.dispatch(message)` /
`lustre.send(runtime, message)` for pushing messages into a running runtime.

Decision rule:

- If the interaction must feel immediate under the user's hand — a drag, a
  slider, a drawer, a form draft — the state belongs in the browser. The author
  of the two source articles reports exactly this: their server-managed drawer
  and dropdown "didn't feel good", and drag-and-drop made it obvious that the
  pointer and its feedback have to stay together. **Opinion**, consistent with
  the latency argument; not measured here.
- If the state is authoritative and shared (tables, admin configuration, lists
  that other users change), a server component keeps one copy of the truth and
  patches the DOM for you.
- Mixing is normal: a server-rendered page with a client island in one region.
  The cost the same author names is that one feature then crosses two source
  trees, so keep the island boundary at a screen region, not inside a form.

## Structure of a client island

`lustre.simple`, `lustre.application`, and `lustre.component` all build the same
shape: `init` returns the model (and effects, once you need them), `update`
returns a new model, `view` returns `Element(message)`. The `application`
signature is verified:

```gleam
pub fn application(
  init init: fn(arguments) -> #(model, Effect(message)),
  update update: fn(model, message) -> #(model, Effect(message)),
  view view: fn(model) -> Element(message),
) -> App(arguments, model, message)
```

Use that shape for small controls too. A typed message and an explicit model
beat a loose event handler, and it is the only form you can test without a
browser.

## Drag and drop

Verified: `lustre/event` 5.7.1 has `on_click`, `on_mouse_down`, `on_mouse_up`,
`on_mouse_enter`, `on_mouse_leave`, `on_mouse_over`, `on_mouse_out`,
`on_keydown`, `on_keyup`, `on_keypress`, `on_input`, `on_change`, `on_check`,
`on_submit`, `on_focus`, `on_blur`, and the generic
`on(name: String, handler: Decoder(message))`. There is **no** drag-and-drop
helper, so `dragstart`, `drag`, `dragend`, `dragover` and `drop` go through
`event.on`.

Model the drag as a state machine, not as flags:

```gleam
pub type Model {
  Idle
  Dragging(item: String, x: Int)
  Dropped(item: String, onto: String)
}
```

Rules that keep it honest:

- The pointer position updates the island's own model. Do not round-trip per
  move; send one message when the drag ends.
- `attribute.draggable(True)` marks a native draggable; native drag events carry
  a `dataTransfer` that is not a plain JSON value, so keep the dragged item in
  your model and use the event only as a signal (**opinion**: this avoids
  depending on browser data-transfer behaviour).
- Render position with `attribute.style` or a CSS class; keep per-frame numbers
  out of the model when CSS can interpolate them.

## Animation

Verified: `lustre 5.7.1` has no helper for animating DOM state — no transition
or keyframe function. The only animation-shaped symbols in the package are the
SVG SMIL elements in `lustre/element/svg` (`animate`, `animate_motion`,
`animate_transform`), which are markup, not a runtime. Animation is CSS
(`attribute.class`, `attribute.style`, your stylesheet) driven by discrete
states in the model. TEA gives you `Idle` and `Dragging`; CSS gives you the
easing between them. **Opinion:** if a gesture needs a value per frame, keep it
in a mutable reference and a CSS variable rather than dispatching a message per
pointer event; measure before believing it.

## Web Components and Shadow DOM

`lustre.component` turns a TEA app into a custom element, and the Shadow DOM is
part of that model. Verified options: `open_shadow_root(open)`,
`adopt_styles(adopt)`, `delegates_focus(delegates)`, `form_associated()`,
`on_connect`, `on_disconnect`, `on_attribute_change(name, decoder)`,
`on_property_change(name, decoder)`, plus the rendering side: `part(name)`,
`exportparts(names)`, `slot(name)`, `default_slot(attributes, fallback)`,
`named_slot(name, attributes, fallback)`, and
`prerender(app, tag, attributes, children)` for declarative shadow DOM.

Verified defaults in `lustre/runtime/app.default_config`: `open_shadow_root:
True`, `adopt_styles: True`.

Consequences worth knowing before you choose a component:

- **Styles do not leak in.** A component's view renders inside its own shadow
  root. Either expose hooks with `part`/`exportparts` and style them from the
  page with `::part(...)`, or let `adopt_styles` copy the page's stylesheets in.
- **Slots are the public API.** Children rendered by the page arrive through
  `default_slot`/`named_slot`, so the component's light DOM stays the caller's
  contract.
- **`register` is browser-only**: `lustre.register(app, name)` returns
  `Result(Nil, Error)` and `lustre.is_browser()` gates it. Register in a client
  entry module, never in shared code.
- **Testing stays in Gleam.** `lustre/dev/simulate` runs the app's update loop
  without a browser (see below), which is the cheapest way to keep a component
  honest.

**Opinion:** use a Web Component when the island must survive inside a page you
do not control, or when you need style isolation. Inside a single Lustre app,
plain functions returning `Element(message)` are simpler and compose better.

## Testing an island without a browser

Verified by compiling and running this on both targets with `lustre 5.7.1`:

```gleam
import lustre/dev/simulate

let app =
  simulate.simple(init: fn(_) { drag.init() }, update: drag.update, view: drag.view)

let model =
  simulate.start(app, Nil)
  |> simulate.message(drag.DragStarted)
  |> simulate.model()
model.dragging |> should.be_true()
```

`simulate` also has `click(simulation, on: query)`, `input(simulation, on:
query, value:)`, `submit(...)`, `event(...)` for a named DOM event, `view`, and
`history`. Pair it with `element.to_string` when the assertion is about markup.
A drag gesture is a state machine; this tests the machine, on both targets, with
no browser and no flake.

## Honest limits

- A server component needs a BEAM host and a live WebSocket; it is not a static
  or edge-rendered page. That is a deployment constraint, not a detail.
- Typed TEA proves the messages and the model fit; it does not prove the
  interaction is usable. Drag and drop still needs a human and a real pointer.
- The ecosystem is small. Expect to write the drag, the animation wiring, and
  the accessibility work yourself; there is no component library to inherit
  them from.
- Style isolation cuts both ways: with a shadow root open by default, a page
  stylesheet cannot reach a component's internals unless the component opts in
  with `part`, `exportparts`, or `adopt_styles`.
