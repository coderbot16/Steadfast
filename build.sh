#!/bin/sh
cat pipeline/pipeline.properties \
	pipeline/profiles.properties \
	pipeline/configs.properties \
	pipeline/uniforms/uncategorized.properties \
	pipeline/uniforms/fog.properties \
	pipeline/uniforms/wind.properties \
	pipeline/uniforms/minishita/common.properties \
	pipeline/uniforms/minishita/sky.properties \
	pipeline/uniforms/minishita/lighting.properties \
	pipeline/uniforms/core/vectors.properties \
> shaders/shaders.properties

rm -rf shaders/common && cp -pr src/common shaders/common