using './main.bicep'

param appName = readEnvironmentVariable('APP_NAME', 'inlogikdemo')
param appImage = readEnvironmentVariable('APP_IMAGE', 'mcr.microsoft.com/dotnet/samples:aspnetapp')
param appPort = readEnvironmentVariable('APP_PORT', '8080')
