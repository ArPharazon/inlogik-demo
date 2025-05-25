using './main.bicep'

param appName = readEnvironmentVariable('APP_NAME', '')
param appImage = readEnvironmentVariable('APP_IMAGE', '')
param appPort = readEnvironmentVariable('APP_PORT', '')
