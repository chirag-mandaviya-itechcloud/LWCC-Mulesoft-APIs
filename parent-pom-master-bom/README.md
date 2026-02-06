> API template requires this parent-pom files to be published in chosen artifact repository (Nexus, artefactory, [azure repo](https://docs.microsoft.com/en-us/azure/devops/pipelines/artifacts/maven?view=azure-devops) etc)
# BOM file
## Getting Started
##### Update bom -> pom.xml
1. Update the `<orgid>` with Anypoint Platform Org Id
2. Publish JSON logger to Anypoint Platform Exchange(under the Org from step 1) and update version <json.logger.ver>
3. Replace the below repository with appropriate artefactory repo where BOM will be published 
```
        <repository>
            <id>mulesoft-consulting</id>
            <url>https://pkgs.dev.azure.com/mulesoft-consulting/_packaging/mulesoft-consulting/maven/v1</url>
            <releases>
                <enabled>true</enabled>
            </releases>
            <snapshots>
                <enabled>true</enabled>
            </snapshots>
        </repository>
```
4. Publish bom -> pom.xml file to chosen artifact repository (Nexus, artefactory, azure repo etc)
> This template uses [Azure repo as example](https://docs.microsoft.com/en-us/azure/devops/pipelines/artifacts/maven?view=azure-devops). 



# Parent-POM file
## Getting Started
##### Update parent-pom -> pom.xml
1. Parent pom uses [bom -> pom.xml](https://github.com/mulesoft-consulting/mule4-rest-api-template/blob/master/parent-pom-files/bom/pom.xml) as parent
```
<parent>
        <groupId>com.mulesoft</groupId>
        <artifactId>solutions-bom</artifactId>
        <version>0.0.1</version>
</parent>
```
2. Update `<parent>`section with published bom file
3. Publish parent-pom -> pom.xml file to chosen artifact repository (Nexus, artefactory, azure repo etc)
> This template uses [Azure repo as example](https://docs.microsoft.com/en-us/azure/devops/pipelines/artifacts/maven?view=azure-devops).
