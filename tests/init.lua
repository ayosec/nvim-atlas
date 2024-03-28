local rtp = vim.opt.runtimepath
rtp:append(".")
rtp:append(vim.fn.getenv("PLENARY"))

vim.cmd("runtime! plugin/plenary.vim")
