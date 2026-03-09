# jobvalley Elixir/Phoenix Conventions

Shared conventions for all jobvalley Elixir/Phoenix projects.

Project-specific context (domain terminology, architecture, bounded contexts, environment variables, file locations) is documented in each project's `AGENTS.md` at the repository root. Read this file at the start of every session to understand the project context.

## Project Guidelines

- Use `mix check` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

### Phoenix v1.8 Guidelines
- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `Web.Layouts` module is aliased in the `web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="fa-x" class="w-5 h-5"/>` component for fontawesome icons. **Always** use the `<.icon>` component for icons, **never** use `Fontawesome` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">`) class with your own values, no default classes are inherited, so your custom classes must fully style the input
- **Always** use the imported `<.button>` component for buttons from `core_components.ex` when available. `<.button>` is imported and using it will save steps and prevent errors

## Elixir Guidelines

- Elixir lists **do not support index based access via the access syntax**
  **Never do this (invalid)**:
      i = 0
      mylist = ["blue", "green"]
      mylist[i]
  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:
      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)
- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:
      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end
      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end
- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix Guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Phoenix Guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.
- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:
      scope "/admin", AppWeb.Admin do
        pipe_through :browser
        live "/users", UserLive, :index
      end
  the UserLive route would point to the `AppWeb.Admin.UserLive` module
- `Phoenix.View` no longer is needed or included with Phoenix, don't use it

## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text` columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such an option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct

## Phoenix HTML Guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html`
- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.
  **Never do this (invalid)**:
      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>
  Instead **always** do this:
      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>
- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:
      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>
  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax
- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:
      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>
  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)
  and **never** do this, since it's invalid (note the missing `[` and `]`):
      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax
- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.
  **Always** do this:
      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>
  and **Never** do this:
      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>

## Phoenix LiveView Guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions in LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`
- Remember anytime you use `phx-hook="MyHook"` and that js hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Never** write embedded `<script>` tags in HEEx. Instead always write your scripts and hooks in the `assets/js` directory and integrate them with the `assets/js/app.js` file

### LiveView Streams

- **Always** use LiveView streams for collections instead of assigning regular lists to avoid memory ballooning and runtime termination:
  - basic append: `stream(socket, :messages, [new_msg])`
  - reset with new items: `stream(socket, :messages, [new_msg], reset: true)`
  - prepend: `stream(socket, :messages, [new_msg], at: -1)`
  - delete: `stream_delete(socket, :messages, msg)`
- When using `stream/3`, the template must 1) set `phx-update="stream"` on the parent element with a DOM id, and 2) consume `@streams.stream_name` using the id as DOM id:
      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>
- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2`. To filter/refresh, **refetch the data and re-stream with `reset: true`**:
      def handle_event("filter", %{"filter" => filter}, socket) do
        messages = list_messages(filter)
        {:noreply,
        socket
        |> assign(:messages_empty?, messages == [])
        |> stream(:messages, messages, reset: true)}
      end
- LiveView streams *do not support counting or empty states*. Track counts with a separate assign. For empty states use Tailwind:
      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @stream.tasks} id={id}>
          {task.name}
        </div>
      </div>
- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView Tests

- Use `Phoenix.LiveViewTest` module and `LazyHTML` for assertions
- Form tests are driven by `render_submit/2` and `render_change/2`
- **Always reference the key element IDs you added in templates** for `element/2`, `has_element/2`, selectors, etc
- **Never** test against raw HTML, **always** use `element/2`, `has_element/2`: `assert has_element?(view, "#my-form")`
- Instead of testing text content (which can change), favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- When facing test failures with element selectors, debug with `LazyHTML`:
      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Form Handling

#### Creating a form from params
    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end
When you pass a map to `to_form/1`, it assumes the map contains form params with string keys. You can specify a name to nest params:
    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### Creating a form from changesets
    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()
In the template:
    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>
Always give the form an explicit, unique DOM ID.

#### Avoiding form errors
**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template:
    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>
And **never** do this:
    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>
- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>`, instead **always use `<.form for={@form} ...>`**. The UI should **always** be driven by a `to_form/2` assigned in the LiveView derived from a changeset

## Mob / Ensemble Programming with AI

We use [mob.sh](https://mob.sh/) for git-based handoffs (`mob start`, `mob next`, `mob done`) and a **session spec file** (`session-spec.md`) as the shared context for both the team and the AI.

### Core Principles

1. **Spec is the source of truth** — every prompt and every change is grounded in the session spec
2. **Small changes only** — max 1–2 files per AI iteration, no "implement the whole feature"
3. **Stop-and-ask** — if more scope is needed, present a bullet-point plan first and wait for team approval
4. **Always runnable** — after every step: tests pass, code compiles, formatting is clean
5. **No blind merges** — the team must understand and accept every change; AI is an accelerator, not an autopilot
6. **Team conventions rule** — always follow `AGENTS.md` standards; flag deviations, don't silently introduce them

### Working Loop

Follow this continuous loop during mob sessions:

**Generate** → **Review** → **Refine** → **Stabilize**

- **Generate**: Implement only the current task from the spec. Keep diffs small (1–2 files). If more is needed, present a plan first.
- **Review** (team-driven): Is the approach correct? Does it match standards? Is it minimal? Does everyone understand?
- **Refine**: Sharpen prompt/spec, simplify code, reduce diff, clarify unclear parts.
- **Stabilize**: Run tests (`mix test`), run checks (`mix check`), update the spec, update `AGENTS.md` if new conventions were established, commit.


## Code Conventions

### Naming
- **Modules**: PascalCase (e.g., `MyApp.Auftrag`)
- **Functions**: snake_case (e.g., `verrechnungssatz_fuer_auftrag_festlegen`)
- **Test classes**: `.test-*` prefix for CSS selectors (e.g., `.test-sva-hinzufuegen`)
- **Variables**: snake_case and full descriptive names, DO NOT use abbreviations

### Comments
- DO NOT add comments to code which explain the behavior of the code
- ONLY add comments when the code deviates from expectation that explain _why_ the code deviates
