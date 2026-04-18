# OmniSerializer

TODO: Delete this and the text below, and describe your gem

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/omni_serializer`. To experiment with that code, run `bin/console` for an interactive prompt.

## Installation

TODO: Replace `UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG` with your gem name right after releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section with instructions to install your gem from git if you don't plan to release to RubyGems.org.

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

## Usage

### JSONAPI parameter paths

`include` always treats dot notation as relationship traversal.

For `filter`, `sort`, `omni:meta`, and `page`, dot notation is interpreted in two layers:

1. The outer key decides the relationship path.
2. The value is parsed by that family’s leaf normalizer at the resolved target resource.

The outer key is treated as a relationship path only when every dotted segment resolves to a relationship from the current resource. If any segment is not a relationship, the whole key stays local and is passed unchanged to the leaf normalizer.

This means path traversal and leaf parsing are separate concerns. A key like `post-author.user-name` is not automatically split into path `post-author` plus leaf `user-name`. If you want to target a leaf through a relationship, the leaf grammar belongs in the value.

Examples:

```text
filter[post-author.id]=abc
```

This stays local to the current resource and is parsed by the filter leaf normalizer as:

```ruby
{ filter: { post_author: { id: 'abc' } } }
```

```text
filter[posts.active-comments][comment-body.eq]=hello
```

This traverses `posts -> active_comments`, then applies the filter leaf to `CommentResource`.

```text
filter[posts][active-comments.comment-body.eq]=hello
```

This traverses only `posts`. The inner key stays local and is parsed against `PostResource`.

```text
sort[posts.active-comments]=-comment-body
omni:meta[posts.active-comments]=current-page,-pagination
page[posts.active-comments][size]=10
```

These all apply at the `posts -> active_comments` path because the full outer key is a pure relationship chain.

```text
filter[posts.active-comments]=hello
```

This still traverses `posts -> active_comments`, but it then fails because `filter` expects a mapping at the target resource.

When a path crosses a polymorphic relationship, a typed segment such as `taggable:posts` may be needed to disambiguate the branch.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/omni_serializer.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
