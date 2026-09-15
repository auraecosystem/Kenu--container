cd hello-world-composite-action
echo "echo Goodbye" > goodbye.sh
git add action.yml
git commit -m "Add action"
git push
git tag -a -m "Description of this release" v1
git push --follow-tags
