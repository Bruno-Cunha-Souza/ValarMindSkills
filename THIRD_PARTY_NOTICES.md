# Third-Party Notices

## caveman (Julius Brussee)

The files in `hooks/` (`caveman-activate.js`, `caveman-mode-tracker.js`, `caveman-config.js`, `caveman-statusline.sh`) are ported from [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) and retain the original MIT license. The three `skills/caveman*/` skills were also modeled on the upstream project.

```
MIT License

Copyright (c) 2024 Julius Brussee

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Modifications from upstream

- Dropped wenyan (Classical Chinese) modes.
- Dropped `compress` mode / `caveman-compress` skill.
- Adjusted slash-command regex to match plugin-namespaced `/valarmind:caveman*` in addition to bare `/caveman*`.
- Added Portuguese (pt-BR) activation/deactivation phrases to the natural-language matchers (`ative caveman`, `modo caveman`, `parar caveman`, `modo normal`).
- Filter logic in `caveman-activate.js` adapted to the `skills/caveman/SKILL.md` table format used in this repository.
