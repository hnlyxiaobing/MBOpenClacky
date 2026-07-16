# Rabbita

A declarative, functional web UI framework inspired by The Elm Architecture.

This project was previously named `Rabbit-TEA` and is now renamed to `rabbita` .

## Features

* Predictable flow 

  State changes follow a single, predictable update path, with explicit side‑effect management.

* Strict Types

  Rigorous types. No `Any` sprawl. No stringly-typed APIs.

* Balanced bundle size

  ~15 KB min+gzip, includes streaming VDOM diff and the MoonBit standard library (DCE via moonc).

* Modular

  Use `Cell` to split logic and reuse stateful views. Skip diff and patching for non-dirty cells.

## Quick Start

Use the [rabbita-template](https://github.com/moonbit-community/rabbita-template) to get started quickly.

## Examples

### Counter 

```mbt nocheck
using @html {div, h1, button}
enum Msg { 
  Inc
  Dec 
}

fn main {
  let app = simple_cell(
    model=0,
    update=(msg, model) => match msg {
      Inc => model + 1
      Dec => model - 1
    },
    view=(emit, model) => div <| [
      h1("\{model}"),
      button(on_click=emit(Inc), "+"),
      button(on_click=emit(Dec), "-"),
    ],
  )
  new(app).mount("app")
}
```

### Multiple cells

Each cell maintains its own model, view, and update logic, and only dirty cells
need VDOM diffing and patching.

```moonbit nocheck
using @html {fragment, input, nothing, ul, li, p}
using @list {type List, empty}

struct Model {
  value : String
  items : Map[String, Bool]
}

enum Msg {
  Add
  Change(String)
  Done(String)
}

/// The todo plan
fn plan(name : String) -> Cell {
  @rabbita.simple_cell(
    model={ value: "", items: {} },
    update=(msg, model) => {
      let { value, items } = model
      match msg {
        Add => { value: "", items: items..set(value, false) }
        Done(key) => { ..model, items: items..set(key, true) }
        Change(value) => { ..model, value, }
      }
    },
    view=(emit, model) => {
      let { value, items } = model
      let items = items.map((todo, done) => {
        let text_style = if done { "text-decoration: line-through" } else { "" }
        li(style=[text_style], [
          p(todo),
          button(on_click=emit(Done(todo)), "done"),
        ])
      })
      div(style=["border: 1px solid black", "padding: 1em"], [
        h1(name),
        ul(items),
        input(input_type=Text, value~, on_change=s => emit(Change(s))),
        button(on_click=emit(Add), "add"),
      ])
    },
  )
}

/// Main app
test {
  struct Model {
    plans : List[Cell]
  }
  enum Msg {
    NewPlan
  }
  let app = @rabbita.simple_cell(
    model={ plans: empty() },
    update=(msg, model) => {
      let id = model.plans.length()
      match msg {
        NewPlan => { plans: model.plans.add(plan("plan \{id}")) }
      }
    },
    view=(emit, model) => {
      fragment([
        div(model.plans.map(x => x.view())),
        button(on_click=emit(NewPlan), "new plan"),
      ])
    },
  )
  @rabbita.new(app).mount("app")
}
```

`Cell` is an opaque model: it is still managed by the outer model, but internal 
details are hidden. `Cell::view()` is a pure function that maps state to HTML. 

Unlike the hooks-style mental model, a cell's lifecycle is explicit: 
if its view is not present in the real DOM, the cell is inactive and messages to
it are ignored. If the model is removed from the outer model, the cell is destroyed
by the garbage collector.

# Used By

[mooncakes.io](https://mooncakes.io)
