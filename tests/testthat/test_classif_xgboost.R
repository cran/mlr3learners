skip_if_not_installed("xgboost")
skip_on_cran()

test_that("autotest", {
  learner = mlr3::lrn("classif.xgboost", nrounds = 5L)
  expect_learner(learner)
  result = run_autotest(learner)
  expect_true(result, info = result$error)
})

test_that("xgboost with softmax", {
  learner = mlr3::lrn("classif.xgboost", nrounds = 5L, objective = "multi:softmax")
  result = run_autotest(learner, predict_types = "response", exclude = "offset_binary")
  expect_true(result, info = result$error)
})

test_that("xgboost with multi:softprob", {
  task = tsk("sonar")
  learner = mlr3::lrn("classif.xgboost", nrounds = 5L, objective = "multi:softprob")
  p = learner$train(task)$predict(task)
  expect_equal(unname(p$score()), 0)
})

test_that("xgboost with binary:logistic", {
  task = tsk("sonar")
  learner = mlr3::lrn("classif.xgboost", nrounds = 5L)
  p = learner$train(task)$predict(task)
  expect_equal(unname(p$score()), 0)
})

test_that("hotstart", {
  task = tsk("iris")

  learner_1 = lrn("classif.xgboost", nrounds = 5L)
  learner_1$train(task)
  expect_equal(learner_1$state$param_vals$nrounds, 5L)
  expect_equal(learner_1$model$niter, 5L)

  hot = HotstartStack$new(learner_1)

  learner_2 = lrn("classif.xgboost", nrounds = 10L)
  learner_2$hotstart_stack = hot
  expect_equal(hot$start_cost(learner_2, task$hash), 5L)
  learner_2$train(task)
  expect_equal(learner_2$model$niter, 10L)
  expect_equal(learner_2$param_set$values$nrounds, 10L)
  expect_equal(learner_2$state$param_vals$nrounds, 10L)

  learner_3 = lrn("classif.xgboost", nrounds = 2L)
  learner_3$hotstart_stack = hot
  expect_equal(hot$start_cost(learner_3, task$hash), NA_real_)
  learner_3$train(task)
  expect_equal(learner_3$model$niter, 2L)
  expect_equal(learner_3$param_set$values$nrounds, 2L)
  expect_equal(learner_3$state$param_vals$nrounds, 2L)

  learner_4 = lrn("classif.xgboost", nrounds = 5L)
  learner_4$hotstart_stack = hot
  expect_equal(hot$start_cost(learner_4, task$hash), -1L)
  learner_4$train(task)
  expect_equal(learner_4$model$niter, 5L)
  expect_equal(learner_4$param_set$values$nrounds, 5L)
  expect_equal(learner_4$state$param_vals$nrounds, 5L)
})

test_that("validation and inner tuning", {
  task = tsk("spam")

  learner = lrn("classif.xgboost",
    nrounds = 10,
    early_stopping_rounds = 1,
    validate = 0.2
  )

  learner$train(task)
  expect_named(learner$model$evaluation_log, c("iter", "test_logloss"))
  expect_list(learner$internal_valid_scores, types = "numeric")
  expect_equal(names(learner$internal_valid_scores), "logloss")

  expect_list(learner$internal_tuned_values, types = "integerish")
  expect_equal(names(learner$internal_tuned_values), "nrounds")

  learner$validate = NULL
  expect_error(learner$train(task), "field 'validate'")

  learner$validate = 0.2
  task$internal_valid_task = NULL
  learner$param_set$set_values(
    early_stopping_rounds = NULL
  )
  learner$train(task)
  expect_equal(learner$internal_tuned_values, NULL)
  expect_named(learner$model$evaluation_log, c("iter", "test_logloss"))
  expect_list(learner$internal_valid_scores, types = "numeric")
  expect_equal(names(learner$internal_valid_scores), "logloss")

  learner = lrn("classif.xgboost",
    nrounds = to_tune(upper = 1000, internal = TRUE),
    validate = 0.2
  )
  s = learner$param_set$search_space()
  expect_error(learner$param_set$convert_internal_search_space(s), "Parameter")
  learner$param_set$set_values(early_stopping_rounds = 10)
  learner$param_set$disable_internal_tuning("nrounds")
  expect_equal(learner$param_set$values$early_stopping_rounds, NULL)

  learner = lrn("classif.xgboost",
    nrounds = 100,
    early_stopping_rounds = 5,
    validate = 0.3
  )
  learner$train(task)
  expect_equal(learner$internal_valid_scores$logloss,
    learner$model$evaluation_log$test_logloss[learner$internal_tuned_values$nrounds])

  learner = lrn("classif.xgboost")
  learner$train(task)
  expect_true(is.null(learner$internal_valid_scores))
  expect_true(is.null(learner$internal_tuned_values))

  learner = lrn("classif.xgboost", validate = 0.3, nrounds = 10)
  learner$train(task)
  expect_equal(learner$internal_valid_scores$logloss, learner$model$evaluation_log$test_logloss[10L])
  expect_true(is.null(learner$internal_tuned_values))

  learner$param_set$set_values(
    nrounds = to_tune(upper = 100, internal = TRUE),
    early_stopping_rounds = 10
  )
  expect_error(
    learner$param_set$convert_internal_search_space(learner$param_set$search_space()),
    "eval_metric"
  )

  learner$param_set$set_values(
    eval_metric = "logloss"
  )
  expect_error(
    learner$param_set$convert_internal_search_space(learner$param_set$search_space()),
    regexp = NA
  )
})

test_that("custom inner validation measure", {

  # internal measure
  task = tsk("sonar")

  learner = lrn("classif.xgboost",
    nrounds = 10,
    objective = "binary:logistic",
    validate = 0.2,
    early_stopping_rounds = 10,
    eval_metric = "error"
  )

  learner$train(task)

  expect_named(learner$model$evaluation_log, c("iter", "test_error"))
  expect_list(learner$internal_valid_scores, types = "numeric")
  expect_equal(names(learner$internal_valid_scores), "error")

  # function
  task = tsk("sonar")

  learner = lrn("classif.xgboost",
    nrounds = 10,
    objective = "binary:logistic",
    validate = 0.2,
    early_stopping_rounds = 10,
    maximize = FALSE
  )

  learner$param_set$set_values(eval_metric = function(preds, dtrain) {
    labels = xgboost::getinfo(dtrain, "label")
    err = as.numeric(sum(labels != (preds > 0))) / length(labels)
    return(list(metric = "error", value = err))
  })
  learner$train(task)

  expect_named(learner$model$evaluation_log, c("iter", "test_error"))
  expect_list(learner$internal_valid_scores, types = "numeric")
  expect_equal(names(learner$internal_valid_scores), "error")


  # binary task and mlr3 measure binary response
  task = tsk("sonar")

  learner = lrn("classif.xgboost",
    nrounds = 10,
    validate = 0.2,
    eval_metric = msr("classif.ce")
  )

  learner$train(task)

  expect_named(learner$model$evaluation_log, c("iter",  "test_classif.ce"))
  expect_numeric(learner$model$evaluation_log$test_classif.ce, len = 10)
  expect_list(learner$internal_valid_scores, types = "numeric")
  expect_equal(names(learner$internal_valid_scores), "classif.ce")

  # binary task and mlr3 measure binary prob
  task = tsk("sonar")

  learner = lrn("classif.xgboost",
    nrounds = 10,
    validate = 0.2,
    early_stopping_rounds = 10,
    predict_type = "prob",
    eval_metric = msr("classif.logloss")
  )

  learner$train(task)

  expect_named(learner$model$evaluation_log, c("iter",  "test_classif.logloss"))
  expect_numeric(learner$model$evaluation_log$test_classif.logloss, len = 10)
  expect_list(learner$internal_valid_scores, types = "numeric")
  expect_equal(names(learner$internal_valid_scores), "classif.logloss")

  # binary task and mlr3 measure multiclass prob
  task = tsk("sonar")

  learner = lrn("classif.xgboost",
    nrounds = 10,
    validate = 0.2,
    early_stopping_rounds = 10,
    predict_type = "prob",
    eval_metric = msr("classif.auc")
  )

  learner$train(task)

  expect_named(learner$model$evaluation_log, c("iter",  "test_classif.auc"))
  expect_numeric(learner$model$evaluation_log$test_classif.auc, len = 10)
  expect_list(learner$internal_valid_scores, types = "numeric")
  expect_equal(names(learner$internal_valid_scores), "classif.auc")

  # multiclass task and mlr3 measure multiclass response
  task = tsk("iris")

  learner = lrn("classif.xgboost",
    nrounds = 10,
    validate = 0.2,
    early_stopping_rounds = 10,
    predict_type = "prob",
    eval_metric = msr("classif.ce")
  )

  learner$train(task)

  expect_named(learner$model$evaluation_log, c("iter",  "test_classif.ce"))
  expect_numeric(learner$model$evaluation_log$test_classif.ce, len = 10)
  expect_list(learner$internal_valid_scores, types = "numeric")
  expect_equal(names(learner$internal_valid_scores), "classif.ce")

  # multiclass task and mlr3 measure multiclass prob
  task = tsk("iris")

  learner = lrn("classif.xgboost",
    nrounds = 10,
    validate = 0.2,
    early_stopping_rounds = 10,
    predict_type = "prob",
    eval_metric = msr("classif.logloss")
  )

  learner$train(task)

  expect_named(learner$model$evaluation_log, c("iter",  "test_classif.logloss"))
  expect_numeric(learner$model$evaluation_log$test_classif.logloss, len = 10)
  expect_list(learner$internal_valid_scores, types = "numeric")
  expect_equal(names(learner$internal_valid_scores), "classif.logloss")
})

test_that("mlr3measures are equal to internal measures", {
  # response
  set.seed(1)
  task = tsk("sonar")

  learner = lrn("classif.xgboost",
    nrounds = 10,
    objective = "binary:logistic",
    validate = 0.2,
    early_stopping_rounds = 10
  )

  learner$param_set$set_values(eval_metric = msr("classif.ce"))
  learner$train(task)
  log_mlr3 = learner$model$evaluation_log

  set.seed(1)
  learner$param_set$set_values(eval_metric = "error")
  learner$train(task)

  log_internal = learner$model$evaluation_log

  expect_equal(log_mlr3$test_classif.ce, log_internal$test_error)

  # prob
  set.seed(1)
  task = tsk("sonar")

  learner = lrn("classif.xgboost",
    nrounds = 10,
    objective = "binary:logistic",
    validate = 0.2,
    early_stopping_rounds = 10
  )

  learner$param_set$set_values(eval_metric = msr("classif.auc"))
  learner$train(task)
  log_mlr3 = learner$model$evaluation_log

  set.seed(1)
  learner$param_set$set_values(eval_metric = "auc")
  learner$train(task)

  log_internal = learner$model$evaluation_log

  expect_equal(log_mlr3$test_classif.auc, log_internal$test_auc)

  # multiclass response
  set.seed(1)
  task = tsk("zoo")

  learner = lrn("classif.xgboost",
    nrounds = 10,
    objective = "multi:softmax",
    validate = 0.5,
    early_stopping_rounds = 10
  )

  learner$param_set$set_values(eval_metric = msr("classif.ce"))
  learner$train(task)
  log_mlr3 = learner$model$evaluation_log

  set.seed(1)
  learner$param_set$set_values(eval_metric = "merror")
  learner$train(task)

  log_internal = learner$model$evaluation_log

  expect_equal(log_mlr3$test_classif.ce, log_internal$test_merror)

  # multiclass prob
  set.seed(1)
  task = tsk("zoo")

  learner = lrn("classif.xgboost",
    nrounds = 10,
    objective = "multi:softprob",
    validate = 0.5,
    early_stopping_rounds = 10
  )

  learner$param_set$set_values(eval_metric = msr("classif.logloss"))
  learner$train(task)
  log_mlr3 = learner$model$evaluation_log

  set.seed(1)
  learner$param_set$set_values(eval_metric = "mlogloss")
  learner$train(task)

  log_internal = learner$model$evaluation_log

  expect_equal(log_mlr3$test_classif.ce, log_internal$test_error)

})

test_that("base_margin (offset)", {
  # binary classification task
  task = tsk("sonar")

  # same task with zero offset (should not affect predictions)
  data = task$data()
  set(data, j = "zeros", value = rep(0, nrow(data)))
  task_offset = as_task_classif(data, target = "Class")
  task_offset$set_col_roles(cols = "zeros", roles = "offset")

  # same task but with a numeric column acting as offset
  task_offset2 = task$clone()
  task_offset2$set_col_roles(cols = "V42", roles = "offset")

  # add predefined internal validation task
  part = partition(task, c(0.6, 0.2)) # 60% train, 20% test, 20% validate
  task$internal_valid_task = part$validation
  task_offset$internal_valid_task = part$validation
  task_offset2$internal_valid_task = part$validation

  l = lrn("classif.xgboost", nrounds = 5, predict_type = "prob")
  l$validate = "predefined"
  p1 = l$train(task, part$train)$predict(task, part$test) # no offset
  p2 = l$train(task_offset, part$train)$predict(task_offset, part$test) # zero offset
  expect_false("zeros" %in% l$model$feature_names) # offset column is not a feature
  p3 = l$train(task_offset2, part$train)$predict(task_offset2, part$test) # non-zero offset
  expect_false("V42" %in% l$model$feature_names) # "V42" column is not a feature

  expect_equal(p1$prob, p2$prob) # zero offset => same predictions
  expect_false(all(p1$prob[, 1L] == p3$prob[, 1L])) # non-zero offset => different predictions

  # multiclass task
  task = tsk("iris")

  # same task with multiclass offset
  data = task$data()
  set(data, j = "offset_setosa", value = runif(nrow(data)))
  set(data, j = "offset_virginica", value = runif(nrow(data)))
  set(data, j = "offset_versicolor", value = runif(nrow(data)))
  task_offset = as_task_classif(data, target = "Species")
  task_offset2 = task_offset$clone()
  task_offset$set_col_roles(cols = c("offset_setosa", "offset_virginica", "offset_versicolor"), roles = "offset")
  task_offset2$set_col_roles(cols = c("offset_setosa", "offset_versicolor"), roles = "offset")
  part = partition(task)

  l = lrn("classif.xgboost", nrounds = 5, predict_type = "prob")
  # xgboost doesn't work with less offset columns than the class labels
  expect_error(l$train(task_offset2), "only 2 offset columns are provided")
  p1 = l$train(task, part$train)$predict(task, part$test) # no offset
  p2 = l$train(task_offset, part$train)$predict(task_offset, part$test) # with offset

  expect_false(all(p1$prob == p2$prob))
})
