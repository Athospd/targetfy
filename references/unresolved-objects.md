# Resolving Unresolved Objects

An **Unresolved Object** is a name the Script Sequence uses but never defines, loads or attaches. Resolve each one with the user before writing any Generated File.

## Search, in this order

1. Other `.R` files in the project: look for an assignment or function definition with that name.
2. `.RData` and `.rds` files whose names match.
3. Installed packages: `Rscript -e 'print(help.search("^<name>$", fields = "alias")$matches[, c("Package", "Topic")])'`. The user's `.Rprofile` may be attaching a package the scripts never load themselves.

## Offer the options that apply

Show the user what you found and where. Mark the best-fitting option as the default.

| Option | When to offer it | What it does |
|---|---|---|
| a. Add the file to the Script Sequence | found in an `.R` file | the file's code becomes Targets |
| b. Load the file in place | found in an `.R` file that only defines functions | `tar_source()` includes that file |
| c. Add the package | found in a package | adds it to `tar_option_set(packages = ...)` |
| d. Track the data file | found in an `.rds` or `.RData` file | adds a `tar_file_read()` Target |
| e. Wait for the user | always | the user fixes their script; search again |
| f. Assume it exists | always | continue; step 4 runs in `--mode static`, and the report says Equivalence is unverified |
| g. Abort | always | stop without writing anything |

For option (a), the new file's position in the Script Sequence is the user's decision: ask for it.

Record every choice in the report.

## Ordering problems

If a later script in the Sequence defines something an earlier one needs, report it as an ordering problem. Leave the order as the user gave it and ask them how to proceed.
