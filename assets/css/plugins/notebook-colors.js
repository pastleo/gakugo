const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = plugin(function ({ addBase }) {
  const palettePath = path.join(__dirname, "../../../priv/notebook_colors.json")
  const palette = JSON.parse(fs.readFileSync(palettePath, "utf8"))

  const lightVars = {}
  const darkVars = {}
  const utilitySelectors = {}

  palette.forEach((color) => {
    lightVars[`--gakugo-notebook-color-${color.name}-foreground`] = color.light.foreground
    lightVars[`--gakugo-notebook-color-${color.name}-background`] = color.light.background
    darkVars[`--gakugo-notebook-color-${color.name}-foreground`] = color.dark.foreground
    darkVars[`--gakugo-notebook-color-${color.name}-background`] = color.dark.background

    utilitySelectors[`.notebook-item-text-${color.name}`] = {
      color: `var(--gakugo-notebook-color-${color.name}-foreground)`,
    }

    utilitySelectors[`.notebook-item-background-${color.name}`] = {
      "background-color": `var(--gakugo-notebook-color-${color.name}-background)`,
    }

    utilitySelectors[`.notebook-color-swatch-${color.name}-foreground`] = {
      "background-color": `var(--gakugo-notebook-color-${color.name}-foreground)`,
    }

    utilitySelectors[`.notebook-color-swatch-${color.name}-background`] = {
      "background-color": `var(--gakugo-notebook-color-${color.name}-background)`,
    }
  })

  addBase({
    ":root": lightVars,
    '@media (prefers-color-scheme: dark)': {
      ':root:not([data-theme])': darkVars,
    },
    '[data-theme="light"]': lightVars,
    '[data-theme="dark"]': darkVars,
    ...utilitySelectors,
  })
})
