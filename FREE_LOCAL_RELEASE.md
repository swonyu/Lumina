# Free local implementation

This source belongs to Lumina trainer, App Store ID 6773973606. Legacy Lumina Coach, App Store ID 6774136758, is a separate scaffold.

## End-user access

Core journal, check-in, workout, meal, habit and progress-photo functions run locally. The app contains no purchase, subscription, paywall or advertising integration. Release coordination must separately verify that the App Store download price is free before submission or release.

Coach chat uses Apple's system on-device language model only when it is already available and supports the selected app language. It requires no separate AI app, account, API key or manual model download. Availability varies by device, system settings, language and system model readiness. The app provides local rules when the model is unavailable, busy or too slow, and labels the answer source. A rules reply is not described as a model-generated answer.

The training screen also provides a local planning checklist. It does not depend on AI availability. Record reflections describe only the supplied saved records; they do not substitute guessed workout counts or fixed energy averages for recorded data.

## Data and model boundaries

The current chat makes no cloud or paid-provider requests. It passes bounded saved-record excerpts and recent conversation excerpts to the system model, explicitly marks incomplete context, counts tokens before inference, limits the response, and supports Stop and navigation cancellation. It does not send photos, credentials or unverified historic AI notes. Model output does not execute record actions or calculate health measurements.

A model refusal is shown as an app notice. It is not retried through another model or the ordinary training rules. A slow canceled generation retains its admission slot until it actually terminates, so repeated retries cannot create overlapping inference tasks.

The historical `GrokService` and `SmartGrokCoach` names remain as local compatibility entry points. Their optional legacy key argument is ignored. They do not read an environment variable, store a credential or contact an API. Existing credentials and account settings have not been altered. Older xAI setup instructions in this repository are historical material and do not apply to this implementation.

## Verification boundaries

The UIQA build injects an unavailable model provider into the chat screen, so the existing offline UI acceptance flow never invokes a real model. The on-device service tests inject controlled responses, including refusal, timeout and deliberately slow cancellation. These checks verify the integration contract, not actual model answer quality.

The Release build uses the real availability-checked system provider. Supported physical-device acceptance, answer quality, accessibility, final signed artifact inspection, Apple processing and App Store review remain distinct release gates. An unsigned archive or passing simulator checks do not establish those outcomes.
