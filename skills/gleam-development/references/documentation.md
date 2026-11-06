# Documentation comments

Load this reference before you write or change a `////` or `///` comment.

This standard uses rules from ASD-STE100 Simplified Technical English. The
goal is text that a reader understands on the first read, and that
`gleam docs build` shows with a clear structure.

`scripts/gleam-doc-check` checks most of these rules. The rules that the
script cannot check are marked *(review)*.

## Language

1. Write one idea in each sentence.
2. Write a maximum of 25 words in a sentence. Write a maximum of 20 words in
   an instruction.
3. Use the present tense and the active voice. Write "Charges the owner", not
   "The owner is charged".
4. Start the summary of a function with a verb that ends in "s": "Returns",
   "Calculates", "Claims". Do not start it with "The" or with a command such
   as "Keep".
5. Start the summary of a type or a constant with a noun phrase: "Why a
   repair claim failed."
6. Use one word for one meaning. Define each domain term in the module's
   `## Terms` table, and then use only that word. *(review)*
7. Keep the articles "a", "an" and "the". Do not write fragments such as "The
   debt at `now`, floored at zero."
8. Write the unit after each number: "seconds", "for each 1,000 HP", "as exact
   decimal text". *(review)*
9. Put code names in backticks: `missing_health`, `None`.
10. Do not write history: no "moved here from", no "was", no references to an
    earlier implementation or to another language. Git holds the history.
    *(review)*

### Banned words

Do not use figurative words or words with more than one meaning. The script
refuses these words in doc comments:

| Do not write | Write |
| --- | --- |
| carries, carry | holds, contains, sends |
| answers | returns |
| seam | boundary, function, module |
| surface | API, page, function |
| rail, lane | the specific path, queue or process |
| derive, derives | calculates |
| crosses | is sent as |
| in front of | before, uses |
| the one | the only, or name the thing |
| simply, just, basically, obviously | (delete the word) |

Add project words with `--words <file>`, one word or phrase on each line.
Write `from => to` to give the replacement that `--fix` uses. A word without
`=>` has no safe replacement, and `--fix` leaves it for you.

## Module comments (`////`)

A module comment has a summary and then sections. Use these sections in this
order. Leave out a section that has no content.

```gleam
//// <Summary: what this module does, in one or two sentences.>
////
//// <Optional: what this module does not do, or which modules it imports.>
////
//// ## Terms
////
//// | Term | Meaning |
//// | --- | --- |
//// | Damage debt | The HP that a mech needs, at the time of the stamp. |
////
//// ## Rules
////
//// 1. The database stores the damage debt, not the current HP.
//// 2. Amounts are exact decimal text. This module never converts an amount
////    to `Float`.
////
//// ## Examples
////
//// ## Related modules
////
//// - `app/repair/session`: one repair session, from start to end.
```

- **Terms**: each domain word that the module uses, with one meaning. Put the
  table in each module, also when another module has the same term. A reader
  must not open a second file to understand this one.
- **Rules**: the invariants of the module, one in each item. A rule is a fact
  that is always true, not a description of the code.
- **Examples**: a short use of the module, if the API is not clear from the
  function docs.
- **Related modules**: the submodules and the modules that a reader usually
  opens next, each with one line.

Use `##` for module sections. `gleam docs` shows the module name as the only
`#` heading.

## Item comments (`///`)

```gleam
/// Claims an instant repair for one mech and charges the owner.
///
/// The charge and the repair happen in one database transaction. If one
/// fails, neither happens.
///
/// ### Errors
///
/// - `NothingToRepair` if the mech has no damage debt.
/// - `InsufficientFunds` if the owner cannot pay the price.
///
/// ### Example
///
/// ```gleam
/// repair.claim(db, mech_id: "m-41")
/// // -> Ok(Receipt(price: "12.50"))
/// ```
pub fn claim(...) -> Result(Receipt, ClaimError)
```

1. Write the summary on the first line.
2. Write the conditions as a list: "If `stamped_at` is `None`, the result is
   `debt`."
3. Use only these headings, with `###`:
   - `### Errors` for a function that returns `Result`, with one item for each
     error variant that it can return. Name the variant in backticks:
     `` `InsufficientFunds` ``, or `` `Refused(TooLow)` `` for a wrapped one.
   - `### Panics` for a function that can panic, with the condition.
   - `### Example` or `### Examples` for a call that is not obvious.
4. Use a note for a rule that the caller must obey:
   `> **Note:** Do not calculate missing HP in a different place.`

Do not use `#` or `##` in an item comment. `gleam docs` shows each function
name as a `##` heading, so a `##` heading in the comment looks like a new
function.

### Types

- Write a `///` comment on each variant of a custom type.
- Write a `///` comment on each labelled field. Include the unit or the
  format. *(review)*

```gleam
/// Why a repair claim failed.
pub type ClaimError {
  /// The mech has no damage debt.
  NothingToRepair
  /// The owner's wallet holds less than the price.
  InsufficientFunds(
    /// The price, as exact decimal text.
    price: String,
  )
}
```

## Coverage

- Each `pub` function, type and constant has a `///` comment.
- Each module has a `////` comment.
- A private function does not need a comment. Use `//` only to give a reason
  that the code cannot show: a workaround, a limit, or why the obvious version
  is wrong.

## Before and after

Before:

```gleam
/// The debt at `now`, floored at zero. A debt with no stamp projects no
/// regeneration: the debt is known but its start time is not, and inventing an
/// elapsed time would heal a wreck for free.
///
/// Public because the credit write derives the same figure in front of the same
/// dials: a second derivation is a second repair model.
```

After:

```gleam
/// Calculates the HP that a mech needs now.
///
/// - If `debt` is `0.0` or less, the result is `0.0`.
/// - If `stamped_at` is `None`, the result is `debt`. Regeneration does not
///   apply, because the start time is unknown.
/// - If `in_bay` is `True`, regeneration uses the bay multiplier.
///
/// > **Note:** `repair/session` uses this function when it credits a repair.
/// > Do not calculate missing HP in a different place.
```

## The checker

```sh
"$skill/scripts/gleam-doc-check" src                    # check one package
"$skill/scripts/gleam-doc-check" --words doc-words.txt src
"$skill/scripts/gleam-doc-check" --write-baseline doc-baseline.txt src
"$skill/scripts/gleam-doc-check" --baseline doc-baseline.txt src
"$skill/scripts/gleam-doc-check" --fix src                 # rewrite the safe findings
"$skill/scripts/gleam-doc-check" --errors src              # check ### Errors sections
```

`--fix` rewrites two kinds of finding in place, and then checks again:

- A banned word that has a replacement: "carries" becomes "holds", and
  "simply" is deleted. The fix keeps the case of the word and does not change
  text in backticks.
- A function summary that starts with a known imperative verb: "Parse"
  becomes "Parses", and "Whether" becomes "Returns whether".

The other findings need a person or an agent. Read the diff before you commit:
a replacement can be correct for the rule and wrong for the sentence.

`--errors` runs `gleam export package-interface`, so the package must build.
It reports the rule `errors-section`:

- A public function that returns `Result(a, E)` has no `### Errors` section.
  `E` must be a custom type of the same package.
- An item names a constructor that is not a variant of `E`. A variant of a
  type that `E` wraps is correct, and so is the name of the type.

The interface does not show which variants a function can return. So the
check does not report a variant that the section leaves out.

The script skips a file that has the word "generated" in its first five
lines.

For an existing project, write a baseline once. The check then fails only on
new findings. When you correct a module, write the baseline again, so that the
file becomes smaller. Do not add new lines to the baseline by hand.
