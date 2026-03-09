defmodule HelloPhoenixWeb.CoreComponents do
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :variant, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@rest[:type] || "button"}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg py-2 px-3",
        "text-sm font-semibold leading-6 text-white active:text-white/80",
        "bg-zinc-900 hover:bg-zinc-700",
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end
end