# Data notice: connectome.json

`App/Resources/connectome.json` is **not** MIT-licensed code. It is
third-party scientific data bundled with this project. Everything else in
this repository is MIT (see [LICENSE](../LICENSE)).

## What it is

A machine-readable subset of the *C. elegans* hermaphrodite connectome:
neuron/cell identities plus ~4,800 chemical and gap-junction edges with EM
section counts. No article text, figures, or full supplementary files.

## Provenance

- Underlying dataset: Cook et al. (2019), *Whole-animal connectomes of both
  Caenorhabditis elegans sexes*, Nature 571, 63–71,
  <https://doi.org/10.1038/s41586-019-1352-7> (author correction July 2020).
  Free-to-read author manuscript: PMCID PMC6889226.
- Converted from the OpenWorm ConnectomeToolbox (MIT-licensed) cache at
  pinned revision `b9c0b4a7bc2ccf47d3ce7aac624e1b3e2ea86254`:
  - `cect/cache/Cook2019HermReader.json`
  - `cect/Cells.py`
- Same data is published for download at <https://wormwiring.org/>.
- Full revision pins and SHA-256 hashes are embedded in the file itself
  (`dataset`, `provenance`).

## Terms

The dataset is © its original authors. No separate redistribution license
was found on the paper, the PMC manuscript, or WormWiring. This project
reuses the numerical connectivity facts with attribution, for
non-commercial use, consistent with long-standing community practice.
If you hold rights in this data and object to its inclusion here, please
open an issue on this repository and it will be removed or replaced.

## Citation

If you use this data, cite:

> Cook, S. J. et al. Whole-animal connectomes of both Caenorhabditis
> elegans sexes. Nature 571, 63–71 (2019).
> <https://doi.org/10.1038/s41586-019-1352-7>
