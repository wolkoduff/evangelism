
#' 
#' BTC/USD prediction using Keras (Tensorflow backend) and GPU
#' 


### 0. Import Dependecies ----
suppressPackageStartupMessages({
  # DL framework
  library(keras)
  # if nessary: install_keras(tensorflow = "gpu")
  # data processing 
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(lubridate)
  library(xts)
  # vizualize
  library(ggplot2)
})

source("LSTM/cryptocurrency_funs.R")
source("LSTM/prediction_funs.R")



### 1. Set parameters ----
epochsN <- 3L
timeStemps <- 48L # 2 days
predictingPeriod <- timeStemps * 30 # 2 months



### 2. Load and preprocessing data ----
data <- loadTrades("BTCUSD",
                   .from = Sys.time() - years(3), 
                   .to = Sys.time(), 
                   .period = to.minutes10) # or read from cache: readRDS("AI-Workshop/data/trades.rds")

ts.plot(data$Close)
ts.plot(data$LogReturn)


mData <- data$LogReturn %>% 
  as_vector %>% 
  get2DTensor(., timeStemps)

sprintf("Working in the Matrix: %s", paste(dim(mData), collapse = ", "))



### 3. Split on train/test datasets ----
splitBy <- dim(mData)[1] - predictingPeriod

x.train <- get3DTensor(mData[1:splitBy, ])
x.test <- get3DTensor(mData[(splitBy + 1):dim(mData)[1], ])

y.train <- mData[2:splitBy, timeStemps]
y.test <- mData[(splitBy + 2):dim(mData)[1], timeStemps]

stopifnot(
  length(y.train) > 0, length(y.test) > 0,
  dim(x.train)[1] == length(y.train),
  dim(x.test)[1] == length(y.test)
)

sprintf("Working in the 3D Matrix: %s", paste(dim(x.train), collapse = ", "))



### 4. Define model  ----
inputShape <- c(dim(x.train)[[2]], # number of time steps
                dim(x.train)[[3]]) # number of features


model <- keras_model_sequential() %>% 
  layer_lstm(
    units = inputShape[1],
    input_shape = inputShape, 
    dropout = .2, recurrent_dropout = .2, 
    return_sequences = T
  ) %>% 
  layer_lstm(
    units = inputShape[1] * 2,
    dropout = .2, recurrent_dropout = .2, 
    return_sequences = F
  ) %>% 
  layer_dense(
    units = 1, 
    activation = "linear"
  )


model %>% compile(
  optimizer = optimizer_rmsprop(), # or "adam"
  loss = "mse" # mean squared error, or mean absolute error (mae)
)

summary(model)



### 5. Train model  ----
model %>% fit(
  x.train, y.train,
  batch_size = 32,
  epochs = epochsN,
  validation_data = list(x.test, y.test),
  verbose = 1
)

# Look what's going on (print in terminal):
#! htop
#! watch -n 0.5 nvidia-smi



### 6. Score model  ----
predict.test <- predict(model, x.test)



### 7. Eval and visualize result ----
results <- combineResultsX(y.test, predict.test[, 1])


ggplot(results %>% filter(Time > max(results$Time) - 100) %>% gather(., "Model", "Price", Prev:Predict, factor_key = T), aes(x = Time)) +
  geom_line(aes(y = Close), color = "red", alpha = .3) +
  geom_line(aes(y = Price, color = Model)) +
  facet_grid(Model ~ .) +
  labs(title = "BTC/USD Stock Price", x = "Date", y = "Close Price") +
  theme_bw()


ggplot(results %>% filter(Time > max(results$Time) - predictingPeriod) %>% gather(., "Model", "Residuals", SMA_residuals:Predict_residuals, factor_key = T), aes(x = Time)) +
  geom_line(aes(y = Prev_residuals), color = "red", alpha = .3) +
  geom_line(aes(y = Residuals, color = Model)) +
  facet_grid(Model ~ .) +
  labs(title = "BTC/USD Stock Price", x = "Date", y = "Close Price") +
  theme_bw()


View(
  results %>% 
    gather(., "Model", "Residuals", Prev_residuals:Predict_residuals, factor_key = T) %>% 
    group_by(Model) %>% 
    summarise(
      TotalLoss = sum(abs(Residuals))
    ) %>% 
    arrange(TotalLoss)
)



### 8. Human vs AI competition ----
View(
  data.frame(
    Close = c(tail(results, 12)[1:10, ]$Close, rep("?", 2))
  )
)

View(
  data.frame(
    Close = tail(results, 12)$Close,
    Predict = tail(results, 12)$Predict
  ) %>% 
  mutate(
    PriceChangeOn = floor(c(NA_real_,  diff(Close))),
    NN_Prediction = floor(Close - Predict)
  ) 
)


