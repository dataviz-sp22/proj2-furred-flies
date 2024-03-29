library(shiny)
library(rsconnect)
library(tidyverse)
library(shinythemes)
library(thematic)
library(urbnmapr)

# Load data --------------------------------------------------------------------
air_quality <- read_csv("data/AllStates_overall.csv", show_col_types = FALSE) %>%
  rename(air_quality_index = `Air Quality Index`) %>%
  mutate(fips = paste0(state_code, county_code), # add fips code
         air_quality_index = factor(air_quality_index,
                             levels = c("Good", "Moderate", "Unhealthy for Sensitive Groups",
                                        "Unhealthy", "Very Unhealthy", "Hazardous"))) %>%
  arrange(year, state, county, pollutant) %>%
  distinct()

pollutant_choices <- air_quality$pollutant %>% unique()
state_choices <- c("Arizona", "California", "Colorado", "Idaho", "Montana",
                   "Nevada", "New Mexico", "Oregon", "Utah", "Washington", "Wyoming")

# summarize air quality by state
air_quality_state <- air_quality %>%
  group_by(year, state, pollutant, units_of_measure) %>%
  summarize(air_qual_year = mean(arithmetic_mean, na.rm = TRUE))

# summarize aqi by state
aqi_state <- air_quality %>%
  group_by(year, state) %>%
  summarize(mean_aqi = mean(AQI, na.rm = TRUE))

# summarize aqi by county
aqi_county <- air_quality %>%
  select(year, state, county, fips, AQI, air_quality_index) %>%
  unique()

# import sf for the county-level map
counties_sf <- get_urbn_map(map = "counties", sf = TRUE)
# only needed if plotting state-level map:
#states_sf <- get_urbn_map(map = "states", sf = TRUE)

# merge air quality data and sf using fips code
counties_air <- left_join(counties_sf, air_quality,
                           by = c("county_fips" = "fips"))

counties_aqi <- left_join(counties_sf, aqi_county,
                          by = c("county_fips" = "fips"))

# extract sf info for Western US states only
WEST.SF <- counties_sf %>% filter(state_name %in% state_choices)

# Define UI --------------------------------------------------------------------
ui <- fluidPage(
  theme = shinytheme("united"),
  titlePanel("Air Quality of Western U.S. Counties in 1971-2021"),
  "A Shiny app built by Caleb Weis, Eva Wu, and Jimin Han",
  br(), br(),
  sidebarLayout(
    sidebarPanel(
      radioButtons(
        inputId = "pollutant",
        label = "Select a pollutant by which air quality is measured:",
        choices = pollutant_choices,
        selected = "PM2.5" # placeholder pollutant
      )
    ),
    mainPanel(
      tabsetPanel(
        # tab 1======
        tabPanel(
          "Map",
          br(),
          sliderInput(
            inputId = "year",
            label = "Select a year:",
            min = 1971,
            max = 2021,
            value = 1971, # placeholder year
            animate = TRUE, # add animation button beside slider
            sep = "" # remove the comma separating thousands
          ),
          textOutput(outputId = "map_text"),
          plotOutput("map")
        ),
        # tab 2======
        tabPanel(
          "AQI Map",
          br(),
          sliderInput(
            inputId = "year_aqi",
            label = "Select a year:",
            min = 1971,
            max = 2021,
            value = 1971, # placeholder year
            animate = TRUE, # add animation button beside slider
            sep = "" # remove the comma separating thousands
          ),
          textOutput(outputId = "aqi_map_text"),
          br(),
          plotOutput("aqi_map_plot")
        ),
        # tab 3======
        tabPanel(
          "Line Plot",
          br(),
          selectInput(
            inputId = "state",
            label = "Select up to 8 states:",
            choices = state_choices,
            selected = "California",
            multiple = TRUE
          ),
          textOutput(outputId = "state_text"),
          br(),
          plotOutput("state_plot")
          ),
        # tab 4======
        tabPanel(
          "AQI Line Plot",
          br(),
          selectInput(
            inputId = "state_aqi",
            label = "Select up to 8 states:",
            choices = state_choices,
            selected = "California",
            multiple = TRUE
          ),
          textOutput(outputId = "aqi_state_text"),
          br(),
          plotOutput("aqi_line_plot")
        ),
        # tab 5======
        tabPanel("Data", DT::dataTableOutput(outputId = "data")),
        # tab 6======
        tabPanel("About", 
                 br(),
                 "In this project, we drew upon data from the US EPA and created 
                 4 visualizations to explore the levels of air pollution, and 
                 the Air Quality Index values, throughout Western U.S. since 1971.",
                 br(), br(),
                 "This app contains 6 tabs. On the left side, you could select 
                 the pollutant type you are interested in. The 'Map' tab shows the 
                 county-level map of air quality measured by your selected 
                 pollutant concentration. The slider under the tab will allow you to
                 select a year or animate using the 'play' button. The map shows
                 a choropleth, using color to indicate pollutant level. Higher 
                 levels of pollutant means worse air quality. The 'AQI Map' tab 
                 shows the county-level map of air quality measured by AQI levels. 
                 You could also use the slider to select or animate through years. 
                 The 'Line Plot' tab shows the air quality measured by your selected 
                 pollutant types. You can select up to 8 states to compare their 
                 air quality trends across years. The 'AQI Line Plot' tab similarly 
                 shows the air quality trend of selected states across years, 
                 but measure by AQI. The 'Data' tab shows the data frame we used 
                 to plot our graphs. Feel free to enter year, state name, county 
                 name, or pollutant type that you are interested in in the search 
                 box to filter the data accordingly.")
      )
    )
  )
)

# Define server function --------------------------------------------
server <- function(input, output) {

  # [tab 1: the map] ========================

  output$map_text <- reactive({
    paste("This map shows the air quality across Western U.S. in", input$year,
          "measured by ", rlang::as_name(input$pollutant)) # this helps recognize input as a string
  })

  output$map <- renderPlot({

    unit <- air_quality %>%
      filter(pollutant == input$pollutant) %>%
      ungroup() %>%
      select(units_of_measure) %>%
      unique()

    counties_air %>%
      filter(year == input$year & pollutant == input$pollutant) %>%
      ggplot() +
      geom_sf(data = WEST.SF) +
      geom_sf(mapping = aes(fill = arithmetic_mean), color = "grey40") +
      coord_sf(datum = NA) +
      scale_fill_gradient(name = paste0("Pollution level \n(", unit, ")"),
                          low = "lightyellow", high = "darkred") +
      theme_void() +
      labs(title = paste0("Map showing county-level air quality measured by ",
                          rlang::as_name(input$pollutant))) +
      theme(legend.position = "left")

  })

  # [tab 2: the aqi map]===================

  output$aqi_map_text <- reactive({
    paste0("This map shows the aqi index by grade across
           Western U.S. in ", input$year_aqi)
  })

  output$aqi_map_plot <- renderPlot({

    # create a color scale
    cols <- c("Good" = "green", "Moderate" = "yellow", "Unhealthy for Sensitive Groups" = "orange",
              "Unhealthy" = "red", "Very Unhealthy" = "purple", "Hazardous" = "maroon")

    counties_aqi %>%
      filter(year == input$year_aqi) %>%
      ggplot() +
      geom_sf(data = WEST.SF) +
      geom_sf(mapping = aes(fill = air_quality_index), color = "grey40") +
      scale_fill_manual(values = cols) +
      coord_sf(datum = NA) +
      labs(title = "Map showing county-level air quality measured by AQI",
           fill = "AQI Levels") +
      theme_void() +
      theme(legend.position = "left")
    
  })

  # [tab 3: the line graph]===================

  output$state_text <- reactive({
    paste0("You've selected ", length(input$state), " state(s). Showing their air
          quality measured by ", rlang::as_name(input$pollutant), " across years...")
  })

  output$state_plot <- renderPlot({

    # verify only 8 or fewer states selected for optimal interpretation
    validate(
      need(
        expr = length(input$state) <= 8,
        message = "Please do not select more than 8 states."
      )
    )

    unit <- air_quality_state %>%
      filter(pollutant == input$pollutant) %>%
      ungroup() %>%
      select(units_of_measure) %>%
      unique()

    air_quality_state %>%
      filter(state %in% input$state & pollutant == input$pollutant) %>%
      ggplot(aes(year, air_qual_year, color = state)) +
      geom_line() +
      theme_light() +
      labs(title = paste0("Air Quality Across Years in ", paste(input$state, collapse = ", ")),
           subtitle = paste0("measured by ", rlang::as_name(input$pollutant)),
           x = "Year", y = paste0("Polution level (", unit, ")"),
           color = "State")

  })

  # [tab 4: the aqi line graph]===================

  output$aqi_state_text <- reactive({
    paste0("You've selected ", length(input$state_aqi), " state(s). Showing their air
          quality measured by AQI (Air Quality Index) across years...")
  })

  output$aqi_line_plot <- renderPlot({

    # verify only 8 or fewer states selected for optimal interpretation
    validate(
      need(
        expr = length(input$state_aqi) <= 8,
        message = "Please do not select more than 8 states."
      )
    )

    aqi_state %>%
      filter(state %in% input$state_aqi) %>%
      ggplot(aes(year, mean_aqi, color = state)) +
      geom_line() +
      theme_light() +
      labs(title = paste0("Air Quality Across Years in ", paste(input$state_aqi, collapse = ", ")),
           subtitle = paste0("measured by AQI (Air Quality Index)"),
           x = "Year", y = "AQI",
           color = "State")

  })

  # [tab 5: the table]==========================

  output$data <- DT::renderDataTable({
    air_quality %>%
      select(year, state, county, fips, AQI, air_quality_index, pollutant, 
             arithmetic_mean, units_of_measure) %>%
      rename(Year = year, State = state, County = county, Unit = units_of_measure,
             `Pollution Level` = arithmetic_mean,
             `Air Quality Category` = air_quality_index, `Air Quality Index` = AQI,
             Pollutant = pollutant, `FIPS Code` = fips) %>%
      arrange(Year, State, `FIPS Code`, Pollutant)

  })

}

# Create the Shiny app object ---------------------------------------
thematic_shiny()
shinyApp(ui = ui, server = server)
