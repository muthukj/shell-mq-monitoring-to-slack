# MQ Monitoring

This script can monitor your linux MQ resources

<b>Pre requisites </b>

1. you need to create an integration to your slack channel.
2. you know the basic shell scripting and MQ

<b>what it does </b>

it'll alert to a slack channel when

1. channel is inactive/retry/stopped
2. space has crossed threshould on the server
3. qdepth has crossed threshould 
4. channel instances are high 
5. Qm is inactive or starting


