# Little Langtale

Use AI generated stories to turn your Kindle screensaver into a language
learning tool.

<img src="images/kindle_oasis.jpeg" width="480">

## Prerequisites

You will need:

- A jailbroken kindle
- The screensaver hack installed (no need for python)
- Onlinescreensaver installed

Further, this will not work if your Kindle is restricted by 'Special Offers'
which will take over your lockscreen instead. Removing this restriction is not
covered by this guide, to pay to remove special offers, check devices under
your Amazon account in a browser, or contact Amazon support.

SSH access to your Kindle is not a strict requirement but it can help with
debugging.

## Installation
### Create and configure environment variables
In the project root, create a `.env` file with the following content.

```
TEST_MODE=false
GEMINI_API_KEY=YOUR-KEY-HERE
```

Test mode lets you create an image without the Gemini API, using example text.

### Deploy to Google cloud
Since this is a Docker container, you can deploy it to various hosts. Here is
the method to deploy it to Google cloud. If you have already installed gcloud
CLI, update it as follows.

```
gcloud components update
```

Connect the gcloud CLI to your GCP account.

```
gcloud auth login
```

Set up your project ID

```
gcloud config set project PROJECT_ID
```

Region settings

```
gcloud config set run/region REGION
```

Docker settings

```
gcloud auth configure-docker
```

Deployment

```
gcloud run deploy sample --port 8080 --source .
```

At this point you will receive the URL where your webapp is running, save it.

You may receive this error at the final step:

```
PERMISSION_DENIED: Build failed because the service account  is missing
required IAM permissions.
```

To resolve, grant the Cloud Run Admin role to the Cloud Build service account:

1. In the Cloud Console, go to the Cloud Build Settings page:

2. Open the Settings page

3. Locate the row with the Cloud Run Admin role and set its Status to ENABLED.

4. In the Additional steps may be required pop-up, click Skip.

Now retry the deployment and it should work.


### Configure Onlinescreensaver
The onlinescreensaver extension needs --no-check-certificate in `bin/update.sh`
as well as changing these lines wherever they appear:

```
  # Incorrect imports
	source config.sh
  source utils.sh

  # Corrected imports
  source ./config.sh
  source ./utils.sh
```