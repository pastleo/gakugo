defmodule GakugoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use GakugoWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :main_container_class, :string,
    default: "mx-auto w-full max-w-6xl space-y-4",
    doc: "class list for the main content container"

  slot :header

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200/40">
      <%= if @header == [] do %>
        <header class="sticky top-0 z-40 border-b border-base-300/80 bg-base-100/90 backdrop-blur-xl">
          <div class="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-primary/40 to-transparent" />

          <nav class="mx-auto flex w-full max-w-6xl items-center justify-between px-4 py-3 sm:px-6 lg:px-8">
            <.link
              navigate={~p"/"}
              class="group flex items-center gap-3 rounded-xl px-2 py-1 transition-colors hover:bg-base-200"
            >
              <img
                src={~p"/images/logo.svg"}
                width="42"
                alt="Gakugo"
                class="shrink-0 transition-transform duration-200 group-hover:scale-105"
              />

              <div class="leading-tight">
                <p class="font-semibold tracking-tight text-base-content">Gakugo</p>
                <p class="text-xs text-base-content/60">Build your language habit</p>
              </div>
            </.link>

            <div class="hidden items-center gap-2 md:flex">
              <.link
                navigate={~p"/units/new"}
                class="rounded-lg px-3 py-2 text-sm font-medium text-base-content/75 transition-colors hover:bg-base-200 hover:text-base-content"
              >
                New unit
              </.link>

              <.link
                href="https://github.com/pastleo/gakugo"
                class="rounded-lg px-3 py-2 text-sm font-medium text-base-content/75 transition-colors hover:bg-base-200 hover:text-base-content"
                target="_blank"
                rel="noreferrer"
              >
                Github
              </.link>

              <div class="mx-1 h-6 w-px bg-base-300" />
              <.theme_toggle />
            </div>

            <details class="group relative md:hidden">
              <summary class="flex list-none cursor-pointer items-center gap-2 rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-sm font-medium text-base-content shadow-sm transition-colors hover:bg-base-200">
                <.icon name="hero-bars-3" class="size-5 group-open:hidden" />
                <.icon name="hero-x-mark" class="hidden size-5 group-open:block" /> Menu
              </summary>

              <div class="absolute right-0 mt-2 w-64 rounded-2xl border border-base-300 bg-base-100 p-3 shadow-lg">
                <div class="space-y-1">
                  <.link
                    navigate={~p"/units/new"}
                    class="block rounded-lg px-3 py-2 text-sm font-medium text-base-content transition-colors hover:bg-base-200"
                  >
                    New unit
                  </.link>

                  <.link
                    href="https://github.com/pastleo/gakugo"
                    class="block rounded-lg px-3 py-2 text-sm font-medium text-base-content transition-colors hover:bg-base-200"
                    target="_blank"
                    rel="noreferrer"
                  >
                    Doc
                  </.link>
                </div>

                <div class="my-3 h-px bg-base-300" />
                <div class="flex items-center justify-between gap-3 px-1">
                  <span class="text-xs font-medium uppercase tracking-wide text-base-content/60">
                    Theme
                  </span>
                  <.theme_toggle />
                </div>
              </div>
            </details>
          </nav>
        </header>
      <% else %>
        {render_slot(@header)}
      <% end %>

      <main class="px-4 py-8 sm:px-6 lg:px-8">
        <div class={@main_container_class}>
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center rounded-full border border-base-300 bg-base-200 p-0.5">
      <div class="absolute left-0 h-8 w-1/3 rounded-full border border-base-300 bg-base-100 shadow-sm transition-[left] [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3" />

      <button
        class="relative flex w-1/3 cursor-pointer items-center justify-center p-2 text-base-content/75 transition-colors hover:text-base-content"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Use system theme"
      >
        <.icon name="hero-computer-desktop" class="size-4" />
      </button>

      <button
        class="relative flex w-1/3 cursor-pointer items-center justify-center p-2 text-base-content/75 transition-colors hover:text-base-content"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Use light theme"
      >
        <.icon name="hero-sun" class="size-4" />
      </button>

      <button
        class="relative flex w-1/3 cursor-pointer items-center justify-center p-2 text-base-content/75 transition-colors hover:text-base-content"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Use dark theme"
      >
        <.icon name="hero-moon" class="size-4" />
      </button>
    </div>
    """
  end
end
