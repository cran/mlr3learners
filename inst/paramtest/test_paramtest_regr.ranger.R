library(mlr3learners)

test_that("regr.ranger", {
  learner = lrn("regr.ranger")
  fun = ranger::ranger
  exclude = c(
    "formula", # handled via mlr3
    "y", # handled via mlr3
    "x", # handled via mlr3
    "data", # handled via mlr3
    "probability", # handled via mlr3
    "case.weights", # handled via mlr3
    "local.importance", # handled via importance() method
    "class.weights", # handled via mlr3
    "inbag", # handled via mlr3 stratification
    "dependent.variable.name", # handled via mlr3
    "status.variable.name", # handled via mlr3
    "classification", # handled via mlr3
    "mtry.ratio", # custom hyperpar
    "time.interest", # survival only
    "quantreg", # handled by predict_type
    "alpha", # survival only
    "minprop" # survival only
  )

  ParamTest = run_paramtest(learner, fun, exclude, tag = "train")
  expect_true(ParamTest, info = paste0(
    "\nMissing parameters in mlr3 param set:\n",
    paste0("- ", ParamTest$missing, "\n", collapse = ""),
    "\nOutdated param or param defined in additional control function not included in list of function definitions:\n",
    paste0("- ", ParamTest$extra, "\n", collapse = ""))
    )
})

test_that("predict regr.ranger", {
  learner = lrn("regr.ranger")
  fun = ranger:::predict.ranger
  exclude = c(
    "quantiles", # handled via mlr3
    "what", # not supported in mlr3
    "predict.all", # not supported in mlr3
    "formula", # handled via mlr3
    "object", # handled via mlr3
    "data", # handled via mlr3
    "type" # handled via mlr3
  )

  ParamTest = run_paramtest(learner, fun, exclude, tag = "predict")
  expect_true(ParamTest, info = paste0(
    "\nMissing parameters in mlr3 param set:\n",
    paste0("- ", ParamTest$missing, "\n", collapse = ""),
    "\nOutdated param or param defined in additional control function not included in list of function definitions:\n",
    paste0("- ", ParamTest$extra, "\n", collapse = ""))
    )
})
