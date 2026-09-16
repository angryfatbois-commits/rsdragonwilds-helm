module.exports = {
  branches: ['main'],
  tagFormat: 'v${version}',
  plugins: [
    '@semantic-release/commit-analyzer',
    '@semantic-release/release-notes-generator',
    ['@semantic-release/exec', {
      prepareCmd: "sed -i -E 's/^version: .*/version: ${nextRelease.version}/; s/^appVersion: .*/appVersion: \"${nextRelease.version}\"/' charts/rsdragonwilds/Chart.yaml",
      publishCmd: 'bash scripts/publish-release.sh ${nextRelease.version}'
    }],
    ['@semantic-release/git', {
      assets: ['charts/rsdragonwilds/Chart.yaml'],
      message: 'chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}'
    }],
    '@semantic-release/github'
  ]
};
