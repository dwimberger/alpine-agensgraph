# alpine-agensgraph

1) To run AgensGraph container:

    docker run -d -e GRAPH_USER=test -e GRAPH_PASSWORD=test -e GRAPH_DB=test -p 5432:5432 dwimberger/agensgraph 

2) To access the container via agens shell:

     docker exec -it --user agraph [YOUR.CONTAINER.NAME.HERE] agens

## Quick Reference

* AgensGraph Quick Guide: http://bitnine.net/support/documents_backup/quick-start-guide-html
* Where to file issues: https://github.com/bitnine-oss/agensgraph/issues


 