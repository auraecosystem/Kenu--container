---
title: Install and run Newman
approved: 2026-03-18T00:00:00.000Z
max-toc-depth: 2
topictype: procedure
---

Newman is built on [Node.js](https://nodejs.org/en/about). To get started, first install Node.js, then install Newman. After installing Newman, you can run your Postman Collections from the command line. You can run collections as an exported JSON file or by passing the URL of the collection to Newman.

## Install Newman

Before installing Newman, make sure you've installed Node.js v16 or later. Follow the [steps to download Node.js](https://nodejs.org/en/download/package-manager/) for your continuous integration (CI) system. (Some CI systems have configurations that pre-install Node.js.)

<Info>
  If you're using an earlier version of Newman, learn more about [Node.js version compatibility with Newman](https://github.com/postmanlabs/newman#nodejs).
</Info>

Install Newman globally so you can run it anywhere on your system. Use the following command:

```bash
npm install -g newman
```

### Update Newman

If you've already installed Newman, you can upgrade to a later version. Learn more about [upgrading to a later version of Newman](https://github.com/postmanlabs/newman/blob/develop/MIGRATION.md).

## Run a collection with Newman

To run a collection with Newman, first [export the collection](/docs/getting-started/importing-and-exporting/exporting-data/#export-collections) as a JSON file. Then run the collection from your file system with the following command:

```bash
newman run my-collection.json
```

<Info>
  You can't use Newman to run scripts and tests in packages that are in your team's [Postman Package Library](/docs/tests-and-scripts/write-scripts/packages/package-library/). Use the [Postman CLI](/docs/postman-cli/postman-cli-overview/) to run the contents of packages from the command line.
</Info>

### Run a collection with a URL

You can run a collection by passing the URL of the collection to Newman. In the following example, substitute the `<collection-id>` with the ID of the collection you want to run:

```bash
newman run https://www.postman.com/collections/<collection-id>
```

You can find the collection ID in Postman. First, expand **Collections** in the sidebar and select a collection. Then click <img alt="Info icon" src="https://assets.postman.com/postman-docs/aether-icons/v12/icon-state-info-stroke.svg#icon" width="20px" /> **Info** in the right sidebar to view and copy the collection ID.

<Info>
  If your collection URL isn't publicly available, [use the Postman API](https://github.com/postmanlabs/newman?tab=readme-ov-file#using-newman-with-the-postman-api) to run your collection with Newman.
</Info>

### Run a collection with an environment

If your collection uses environment variables, you must provide the [environment](/docs/use/send-requests/variables/managing-environments/) used in your collection. [Export the environment](/docs/getting-started/importing-and-exporting/exporting-data/#export-environments) from Postman and include it with the `-e` flag. For example:

```bash
newman run my-collection.json -e dev-environment.json
```

<Info>
  Newman doesn't support OAuth 2.0 authentication. To learn how to use an OAuth 2.0 token with Newman, see [OAuth 2.0 overview](/docs/use/send-requests/authorization/oauth-20/#oauth-20-overview).
</Info>

### Example collection run with failing tests

The following example shows the results of a collection run in Newman with failing tests.

![Newman tests example](https://assets.postman.com/postman-docs/v11/newman-test-example-v11-12.jpg)

In the output, `test-scripts` refers to [post-response scripts](/docs/tests-and-scripts/write-scripts/test-scripts/). Newman supports the same [libraries and objects](/docs/tests-and-scripts/write-scripts/postman-sandbox-reference/overview/) as Postman for pre-request and post-response scripts.

<Info>
  You can export the run results, including all requests and tests, to a file using [Newman's built-in reporters](/docs/reference/newman-cli/newman-built-in-reporters/).
</Info>

## Customize a collection run

Newman provides a rich set of options for customizing a collection run. To learn more, see the [Newman command reference](/docs/reference/newman-cli/newman-options/).

## Using Newman with CI/CD

By default, Newman exits with a status code of `0` if everything runs as expected without any exceptions. You can configure your continuous integration (CI) tool to pass or fail a build based on Newman's exit codes.

Use the [`--bail` option](/docs/reference/newman-cli/newman-options/#more-configuration-options) to make Newman stop a run if it encounters a test case error with a status code of `1`. This status code can then be used by your CI tool or build system.

## Using Newman as a Node.js library

You can use Newman within your JavaScript projects as a Node.js module. The entire set of Newman CLI functionality is available to use programmatically. The following example runs a collection by reading a JSON collection stored in your file system:

```javascript
const newman = require('newman'); // require Newman in your project

// call newman.run to pass the `options` object and wait for callback
newman.run({
    collection: require('./sample-collection.json'),
    reporters: 'cli'
}, function (err) {
    if (err) { throw err; }
    console.log('collection run complete!');
});
```

<Info>
  For the complete list of `newman.run` options, see [API Reference](https://github.com/postmanlabs/newman#api-reference) on GitHub.
</Info>
