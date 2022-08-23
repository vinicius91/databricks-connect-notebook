# databricks-connect-notebook
A Jupyter Server with support to Databricks Connect.

This can be used to access your Databricks environment from your IDE and send jobs directly into a cluster.


## Execution

1. Build the docker environment;
2. `docker compose up`
3. Access the notebook container shell and configure your `databricks-connect` setup;
4. Connect your IDE to the notebook server;
5. Have fun!


## Sources 
This environment is based on:
- [Jupyter's Docker Stacks](https://github.com/jupyter/docker-stacks)
- [eclipse-temurin](https://github.com/docker-library/repo-info/tree/master/repos/eclipse-temurin)
