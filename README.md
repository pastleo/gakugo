# Gakugo

```bash
git clone --recursive https://github.com/pastleo/gakugo.git
cp gakugo-anki-compose/compose.dev.yml gakugo-anki-compose/compose.yml
```

To start your Phoenix dev server:

* You need ollama running locally for AI features
* Run `mix setup` to install and setup dependencies
* `cd gakugo-anki-compose && docker compose up` for anki-sync-server
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
