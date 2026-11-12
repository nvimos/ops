# SYSTEM DIRECTIVE: Clean Declarative UI Architecture

## Purpose

Enforce strict design rules to prevent the "Pyramid of Doom", eliminate deep
inline nesting, decouple business logic from presentation, and adhere to
modular architecture across all declarative UI frameworks (e.g., Flutter,
React, SwiftUI).

---

## Directives

### 1. Enforce Component Composition & Depth Limits

* **Max Nesting Depth:**
  Do NOT nest layout widgets (`Column`, `Row`,
  `Container`, `Padding`, `div`, etc.) more than **3 levels deep** inline
  within a single `build` method or render function.
* **Table of Contents Rule:** Top-level screen components must read like a
  high-level overview.
* **Line Limit:** If a single component or `build` function exceeds **50
  lines**, immediately extract cohesive visual blocks into distinct, named
  sub-components.

### 2. Mandate Data-Driven Rendering

* **No Hardcoded Layout Duplication:** Never manually write out sequential, repetitive blocks of near-identical UI
  elements.
* **Model First:** Define state models, configurations, or data arrays *upfront* outside the layout logic.
* **Declarative Mapping:** Use declarative mapping patterns or native builders (e.g., `.map()`, `ListView.builder`) to project data arrays into UI components.

### 3. Decouple Logic and Presentation

* **Zero Inline Logic Bloat:** Do NOT write state mutations, multi-line logic, async calls, or data formatting inline within event handlers (`onPressed`, `onClick`, `onChange`).
* **Delegate Callbacks:** Pass callback references to top-level handlers or delegate all business logic to external controllers, ViewModels, or dedicated helper methods.
* **Pure Presentation:** Ensure UI components only care about *how things look*, not *how things process*.

### 4. Apply Atomic Design Hierarchies

Organize UI components strictly according to responsibility:

* **Atoms:** Single-purpose, primitive elements (Buttons, Badges, Icons, Input fields).
* **Molecules:** Small functional combinations of atoms (e.g., a labeled input box or a custom list tile).
* **Organisms:** Complex, self-contained layout sections (e.g., a navigation header, a product grid).
* **Templates / Pages:** Page-level structural shells that compose organisms together.

*Rule:* Lower-level components (Atoms & Molecules) must remain "dumb"—they should only accept configuration props/parameters and emit user-event callbacks upward.
