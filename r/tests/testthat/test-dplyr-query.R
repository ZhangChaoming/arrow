# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

skip_if(on_old_windows())

library(dplyr, warn.conflicts = FALSE)
library(stringr)

tbl <- example_data
# Add some better string data
tbl$verses <- verses[[1]]
# c(" a ", "  b  ", "   c   ", ...) increasing padding
# nchar =   3  5  7  9 11 13 15 17 19 21
tbl$padded_strings <- stringr::str_pad(letters[1:10], width = 2 * (1:10) + 1, side = "both")
tbl$another_chr <- tail(letters, 10)

test_that("basic select/filter/collect", {
  batch <- record_batch(tbl)

  b2 <- batch %>%
    select(int, chr) %>%
    filter(int > 5)

  expect_s3_class(b2, "arrow_dplyr_query")
  t2 <- collect(b2)
  expect_equal(t2, tbl[tbl$int > 5 & !is.na(tbl$int), c("int", "chr")])
  # Test that the original object is not affected
  expect_identical(collect(batch), tbl)
})

test_that("dim() on query", {
  compare_dplyr_binding(
    .input %>%
      filter(int > 5) %>%
      select(int, chr) %>%
      dim(),
    tbl
  )
})

test_that("Print method", {
  expect_output(
    record_batch(tbl) %>%
      filter(dbl > 2, chr == "d" | chr == "f") %>%
      select(chr, int, lgl) %>%
      filter(int < 5) %>%
      select(int, chr) %>%
      print(),
    'RecordBatch (query)
int: int32
chr: string

* Filter: (((dbl > 2) and ((chr == "d") or (chr == "f"))) and (int < 5))
See $.data for the source Arrow object',
    fixed = TRUE
  )
})

test_that("pull", {
  compare_dplyr_binding(
    .input %>% pull(),
    tbl
  )
  compare_dplyr_binding(
    .input %>% pull(1),
    tbl
  )
  compare_dplyr_binding(
    .input %>% pull(chr),
    tbl
  )
  compare_dplyr_binding(
    .input %>%
      filter(int > 4) %>%
      rename(strng = chr) %>%
      pull(strng),
    tbl
  )
})

test_that("collect(as_data_frame=FALSE)", {
  batch <- record_batch(tbl)

  b1 <- batch %>% collect(as_data_frame = FALSE)

  expect_r6_class(b1, "RecordBatch")

  b2 <- batch %>%
    select(int, chr) %>%
    filter(int > 5) %>%
    collect(as_data_frame = FALSE)

  # collect(as_data_frame = FALSE) always returns Table now
  expect_r6_class(b2, "Table")
  expected <- tbl[tbl$int > 5 & !is.na(tbl$int), c("int", "chr")]
  expect_equal(as.data.frame(b2), expected)

  b3 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    collect(as_data_frame = FALSE)
  expect_r6_class(b3, "Table")
  expect_equal(as.data.frame(b3), set_names(expected, c("int", "strng")))

  b4 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    group_by(int) %>%
    collect(as_data_frame = FALSE)
  expect_s3_class(b4, "arrow_dplyr_query")
  expect_equal(
    as.data.frame(b4),
    expected %>%
      rename(strng = chr) %>%
      group_by(int)
  )
})

test_that("compute()", {
  batch <- record_batch(tbl)

  b1 <- batch %>% compute()

  expect_r6_class(b1, "RecordBatch")

  b2 <- batch %>%
    select(int, chr) %>%
    filter(int > 5) %>%
    compute()

  expect_r6_class(b2, "Table")
  expected <- tbl[tbl$int > 5 & !is.na(tbl$int), c("int", "chr")]
  expect_equal(as.data.frame(b2), expected)

  b3 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    compute()
  expect_r6_class(b3, "Table")
  expect_equal(as.data.frame(b3), set_names(expected, c("int", "strng")))

  b4 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    group_by(int) %>%
    compute()
  expect_s3_class(b4, "arrow_dplyr_query")
  expect_equal(
    as.data.frame(b4),
    expected %>%
      rename(strng = chr) %>%
      group_by(int)
  )
})

test_that("head", {
  batch <- record_batch(tbl)

  b2 <- batch %>%
    select(int, chr) %>%
    filter(int > 5) %>%
    head(2)
  expect_s3_class(b2, "arrow_dplyr_query")
  expected <- tbl[tbl$int > 5 & !is.na(tbl$int), c("int", "chr")][1:2, ]
  expect_equal(collect(b2), expected)

  b3 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    head(2)
  expect_s3_class(b3, "arrow_dplyr_query")
  expect_equal(as.data.frame(b3), set_names(expected, c("int", "strng")))

  b4 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    group_by(int) %>%
    head(2)
  expect_s3_class(b4, "arrow_dplyr_query")
  expect_equal(
    as.data.frame(b4),
    expected %>%
      rename(strng = chr) %>%
      group_by(int)
  )

  expect_equal(
    batch %>%
      select(int, strng = chr) %>%
      filter(int > 5) %>%
      head(2) %>%
      mutate(twice = int * 2) %>%
      collect(),
    expected %>%
      rename(strng = chr) %>%
      mutate(twice = int * 2)
  )

  # This would fail if we evaluated head() after filter()
  expect_equal(
    batch %>%
      select(int, strng = chr) %>%
      head(2) %>%
      filter(int > 5) %>%
      collect(),
    expected %>%
      rename(strng = chr) %>%
      filter(FALSE)
  )
})

test_that("arrange then head returns the right data (ARROW-14162)", {
  compare_dplyr_binding(
    .input %>%
      # mpg has ties so we need to sort by two things to get deterministic order
      arrange(mpg, disp) %>%
      head(4) %>%
      collect(),
    mtcars,
    ignore_attr = "row.names"
  )
})

test_that("arrange then tail returns the right data", {
  compare_dplyr_binding(
    .input %>%
      # mpg has ties so we need to sort by two things to get deterministic order
      arrange(mpg, disp) %>%
      tail(4) %>%
      collect(),
    mtcars,
    ignore_attr = "row.names"
  )
})

test_that("tail", {
  batch <- record_batch(tbl)

  b2 <- batch %>%
    select(int, chr) %>%
    filter(int > 5) %>%
    arrange(int) %>%
    tail(2)

  expect_s3_class(b2, "arrow_dplyr_query")
  expected <- tail(tbl[tbl$int > 5 & !is.na(tbl$int), c("int", "chr")], 2)
  expect_equal(as.data.frame(b2), expected)

  b3 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    arrange(int) %>%
    tail(2)
  expect_s3_class(b3, "arrow_dplyr_query")
  expect_equal(as.data.frame(b3), set_names(expected, c("int", "strng")))

  b4 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    group_by(int) %>%
    arrange(int) %>%
    tail(2)
  expect_s3_class(b4, "arrow_dplyr_query")
  expect_equal(
    as.data.frame(b4),
    expected %>%
      rename(strng = chr) %>%
      group_by(int)
  )
})

test_that("No duplicate field names are allowed in an arrow_dplyr_query", {
  expect_error(
    Table$create(tbl, tbl) %>%
      filter(int > 0),
    regexp = paste0(
      'The following field names were found more than once in the data: "int", "dbl", ',
      '"dbl2", "lgl", "false", "chr", "fct", "verses", "padded_strings"'
    )
  )
})

test_that("all_sources() finds all data sources in a query", {
  skip_if_not_available("dataset")
  tab <- Table$create(a = 1)
  ds <- InMemoryDataset$create(tab)
  expect_equal(all_sources(tab), list(tab))
  expect_equal(
    tab %>%
      filter(a > 0) %>%
      summarize(a = sum(a)) %>%
      arrange(desc(a)) %>%
      all_sources(),
    list(tab)
  )
  expect_equal(
    tab %>%
      filter(a > 0) %>%
      union_all(ds) %>%
      all_sources(),
    list(tab, ds)
  )

  expect_equal(
    tab %>%
      filter(a > 0) %>%
      union_all(ds) %>%
      left_join(tab) %>%
      all_sources(),
    list(tab, ds, tab)
  )
  expect_equal(
    tab %>%
      filter(a > 0) %>%
      union_all(left_join(ds, tab)) %>%
      left_join(tab) %>%
      all_sources(),
    list(tab, ds, tab, tab)
  )
})

test_that("query_on_dataset() looks at all data sources in a query", {
  skip_if_not_available("dataset")
  tab <- Table$create(a = 1)
  ds <- InMemoryDataset$create(tab)
  expect_false(query_on_dataset(tab))
  expect_true(query_on_dataset(ds))
  expect_false(
    tab %>%
      filter(a > 0) %>%
      summarize(a = sum(a)) %>%
      arrange(desc(a)) %>%
      query_on_dataset()
  )
  expect_true(
    tab %>%
      filter(a > 0) %>%
      union_all(ds) %>%
      query_on_dataset()
  )

  expect_true(
    tab %>%
      filter(a > 0) %>%
      union_all(left_join(ds, tab)) %>%
      left_join(tab) %>%
      query_on_dataset()
  )
  expect_false(
    tab %>%
      filter(a > 0) %>%
      union_all(left_join(tab, tab)) %>%
      left_join(tab) %>%
      query_on_dataset()
  )
})

test_that("query_can_stream()", {
  skip_if_not_available("dataset")
  tab <- Table$create(a = 1)
  ds <- InMemoryDataset$create(tab)
  expect_true(query_can_stream(tab))
  expect_true(query_can_stream(ds))
  expect_true(query_can_stream(NULL))
  expect_true(
    ds %>%
      filter(a > 0) %>%
      query_can_stream()
  )
  expect_false(
    tab %>%
      filter(a > 0) %>%
      arrange(desc(a)) %>%
      query_can_stream()
  )
  expect_false(
    tab %>%
      filter(a > 0) %>%
      summarize(a = sum(a)) %>%
      query_can_stream()
  )
  expect_true(
    tab %>%
      filter(a > 0) %>%
      union_all(ds) %>%
      query_can_stream()
  )
  expect_false(
    tab %>%
      filter(a > 0) %>%
      union_all(summarize(ds, a = sum(a))) %>%
      query_can_stream()
  )

  expect_true(
    tab %>%
      filter(a > 0) %>%
      union_all(left_join(ds, tab)) %>%
      left_join(tab) %>%
      query_can_stream()
  )
  expect_true(
    tab %>%
      filter(a > 0) %>%
      union_all(left_join(tab, tab)) %>%
      left_join(tab) %>%
      query_can_stream()
  )
  expect_false(
    tab %>%
      filter(a > 0) %>%
      union_all(left_join(tab, tab)) %>%
      left_join(ds) %>%
      query_can_stream()
  )
  expect_false(
    tab %>%
      filter(a > 0) %>%
      arrange(a) %>%
      union_all(left_join(tab, tab)) %>%
      left_join(tab) %>%
      query_can_stream()
  )
})
