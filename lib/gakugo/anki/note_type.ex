defmodule Gakugo.Anki.NoteType do
  @moduledoc false

  @shared_css """
  .gakugo-card {
    font-family: "Hiragino Sans", "Hiragino Kaku Gothic Pro", "Yu Gothic", "Meiryo", sans-serif;
    font-size: 16px;
    padding: 16px 18px 18px;
    text-align: left;
    line-height: 1.4;
  }
  .gakugo-notebook {
    list-style: none;
    margin: 0;
    padding: 0;
  }
  .gakugo-notebook li {
    margin: 0.24rem 0;
  }
  .gakugo-page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
    margin-bottom: 0.9rem;
  }
  .gakugo-page-title {
    font-size: 1.18rem;
    font-weight: 800;
    letter-spacing: -0.01em;
  }
  .gakugo-toggle-answers-btn {
    border: 1px solid #475569;
    border-radius: 9999px;
    padding: 0.28rem 0.8rem;
    font-size: 0.72rem;
    line-height: 1;
    white-space: nowrap;
    background: rgba(51, 65, 85, 0.22);
    color: inherit;
    cursor: pointer;
    transition: background-color 120ms ease, border-color 120ms ease;
  }
  .gakugo-toggle-answers-btn:hover {
    background: rgba(51, 65, 85, 0.34);
    border-color: #64748b;
  }
  .gakugo-toggle-answers-btn.is-active {
    background: rgba(245, 158, 11, 0.2);
    border-color: rgba(245, 158, 11, 0.6);
  }
  .gakugo-card.is-question .gakugo-toggle-answers-btn {
    display: none;
  }
  .gakugo-row {
    display: flex;
    align-items: flex-start;
    gap: 0.55rem;
    min-height: 1.55rem;
  }
  .gakugo-marker {
    width: 1rem;
    flex: 0 0 1rem;
    display: inline-flex;
    justify-content: center;
    align-items: center;
    padding-top: 0.55rem;
    color: rgba(148, 163, 184, 0.95);
    font-size: 0.95rem;
    line-height: 1;
  }
  .gakugo-marker.is-target {
    color: #fbbf24;
    text-shadow: 0 0 10px rgba(251, 191, 36, 0.35);
  }
  .gakugo-node {
    flex: 1 1 auto;
    min-width: 0;
    border-radius: 0.85rem;
    padding: 0.42rem 0.72rem;
    box-sizing: border-box;
  }
  .gakugo-node > * {
    position: relative;
    z-index: 1;
  }
  .gakugo-node > *:first-child {
    margin-top: 0;
  }
  .gakugo-node > *:last-child {
    margin-bottom: 0;
  }
  .gakugo-node p,
  .gakugo-node ul,
  .gakugo-node ol,
  .gakugo-node pre,
  .gakugo-node blockquote,
  .gakugo-node h1,
  .gakugo-node h2,
  .gakugo-node h3,
  .gakugo-node h4,
  .gakugo-node h5,
  .gakugo-node h6 {
    margin: 0.2rem 0;
  }
  .gakugo-node.has-text-color {
    color: var(--gakugo-text-light);
  }
  .gakugo-node.has-background-color {
    background: var(--gakugo-bg-light);
  }
  .gakugo-node.is-tree-focus {
    position: relative;
    isolation: isolate;
    overflow: hidden;
  }
  .gakugo-node.is-tree-focus::before {
    content: "";
    position: absolute;
    inset: 0;
    border-radius: inherit;
    background: rgba(245, 158, 11, 1);
    opacity: 0.12;
    z-index: 0;
    pointer-events: none;
    animation: gakugo-focus-pulse 1.7s ease-in-out infinite alternate;
  }
  .gakugo-node.is-target {
    box-shadow: inset 0 0 0 1px rgba(251, 191, 36, 0.5), 0 0 0 1px rgba(251, 191, 36, 0.2);
    font-weight: 700;
  }
  .gakugo-occlusion {
    display: block;
    border-radius: 0.5rem;
    overflow: hidden;
  }
  .gakugo-occlusion-mask {
    display: block;
    min-height: 1.35em;
    border-radius: 0.5rem;
    background: #475569;
    background-size: 400% 100%;
    animation: gakugo-skeleton 1.7s ease-in-out infinite;
  }
  .gakugo-occlusion-answer {
    display: none;
  }
  .gakugo-card.is-answer .gakugo-occlusion.is-current .gakugo-occlusion-mask {
    display: none;
  }
  .gakugo-card.is-answer .gakugo-occlusion.is-current .gakugo-occlusion-answer {
    display: block;
  }
  .gakugo-card.reveal-other-answers .gakugo-occlusion.is-other .gakugo-occlusion-mask {
    display: none;
  }
  .gakugo-card.reveal-other-answers .gakugo-occlusion.is-other .gakugo-occlusion-answer {
    display: block;
  }
  .nightMode .gakugo-card {
    color: #e5e7eb;
  }
  .nightMode .gakugo-node.has-text-color {
    color: var(--gakugo-text-dark);
  }
  .nightMode .gakugo-node.has-background-color {
    background: var(--gakugo-bg-dark);
  }
  .nightMode .gakugo-node.is-tree-focus {
    position: relative;
  }
  .nightMode .gakugo-node.is-tree-focus::before {
    background: rgba(251, 191, 36, 1);
    opacity: 0.14;
  }
  .nightMode .gakugo-occlusion-mask {
    background: #334155;
  }
  .nightMode .gakugo-toggle-answers-btn {
    border-color: #64748b;
    background: rgba(30, 41, 59, 0.82);
  }
  .nightMode .gakugo-toggle-answers-btn:hover {
    background: rgba(51, 65, 85, 0.94);
  }
  @keyframes gakugo-skeleton {
    0% {
      background-position: 100% 50%;
    }
    100% {
      background-position: 0 50%;
    }
  }
  @keyframes gakugo-focus-pulse {
    0% {
      opacity: 0.02;
    }
    100% {
      opacity: 0.2;
    }
  }
  """

  def options do
    [
      {Gakugo.Anki.PageNote.Type.label(), Gakugo.Anki.PageNote.Type.id()},
      {Gakugo.Anki.SimpleNote.Type.label(), Gakugo.Anki.SimpleNote.Type.id()}
    ]
  end

  def default_id, do: Gakugo.Anki.PageNote.Type.id()

  def fetch!(note_type_id) do
    case note_type_id do
      "page_note" -> Gakugo.Anki.PageNote.Type
      "simple_note" -> Gakugo.Anki.SimpleNote.Type
      _ -> raise ArgumentError, "unknown Anki note type: #{inspect(note_type_id)}"
    end
  end

  def shared_css, do: @shared_css

  def card_template(side_class) do
    """
    <div class="gakugo-card #{side_class}">
      <div class="content">{{Content}}</div>
      <script>
        (function () {
          function gakugoScrollTargetIntoView() {
            var target = document.querySelector('.gakugo-node.is-target');
            if (!target) return;
            try {
              target.scrollIntoView({ block: 'center', inline: 'nearest' });
            } catch (_error) {
              target.scrollIntoView();
            }
          }

          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function () {
              setTimeout(gakugoScrollTargetIntoView, 0);
            }, { once: true });
          } else {
            setTimeout(gakugoScrollTargetIntoView, 0);
          }
        })();
      </script>
    </div>
    """
  end
end
