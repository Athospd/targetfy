# Renders the walkthrough project's targetfy-report.md to a dark HTML page
# (GitHub-flavoured tables), for a headless-browser screenshot.
args <- commandArgs(trailingOnly = TRUE)
md <- paste(readLines(args[[1]], encoding = "UTF-8"), collapse = "\n")
body <- commonmark::markdown_html(md, extensions = TRUE)
css <- '
body{background:#0f1520;color:#e6edf6;font-family:"Segoe UI",sans-serif;font-size:22px;
     line-height:1.55;margin:0;padding:48px 72px;width:1456px}
h1{font-size:44px;margin:0 0 18px;border-bottom:1px solid #2a3650;padding-bottom:12px}
h2{font-size:30px;margin:34px 0 12px;color:#3cc8b4;border-bottom:1px solid #222c40;padding-bottom:6px}
code{font-family:"Cascadia Mono",Consolas,monospace;background:#1b2436;padding:2px 7px;
     border-radius:6px;font-size:19px}
table{border-collapse:collapse;width:100%;margin:8px 0}
th,td{border:1px solid #2a3650;padding:7px 12px;text-align:left}
th{background:#1b2436}
tr:nth-child(even) td{background:#131b29}
strong{color:#ffffff}
ul{padding-left:26px;margin:6px 0 4px}
li{margin:2px 0}'
writeLines(c('<!DOCTYPE html><html><head><meta charset="utf-8"><style>', css,
             '</style></head><body>', body, '</body></html>'),
           args[[2]], useBytes = TRUE)
