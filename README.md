# kubectl

`kubectl` is an emacs package to control kubernetes, with TRAMP integration. It is heavily inspired, and in a
way a merger, of the following previous packages:

- [kubernetes-el](https://github.com/chrisbarrett/kubernetes-el)
- [kubernetes-tramp](https://github.com/gruggiero/kubernetes-tramp)
- and the [conquering kubernetes with
  emacs](https://www.reddit.com/r/emacs/comments/ci7s53/conquering_kubernetes_with_emacs/) talk

The reason I wrote my own package is that the above approaches are unaware of each other, and I wanted the following features:

- Pervasive support for multiple `kubectl` configurations, and namespaces
- TRAMP support (for docker containers that have a valid shell when `exec`'ed into)
- Individual buffers for individual lists, like `dired` does (instead of recycling one buffer).

# Prerequisites

You need to have `kubectl` (the kubernetes command-line tool) setup with one or more configs.

# Usage

Install by cloning this repository, and inserting the following into your `init.el`:

```elisp
(add-to-list 'load-path "~/path-to-cloned-repository/kubectl")
(require 'kubectl)
```

## Viewing deployments

Run `kubectl-deployments` to view the kubernetes deployments on a particular config/namespace. It will ask
which config and namespace to use. From there, you can use the following key bindings:

- `c` to switch kubernetes context (and select a new namespace in the new context)
- `n` to switch kubernetes namespace within the same context
- `g` to re-load the deployments
- `o` or `RET` to "open" a deployment and view all pods running under it
- `i` to inspect a deployment, viewing its YAML source

## Viewing pods

After pressing `RET` on a deployment, a list of pods and their state is shown in a new buffer. Here you have
the following key bindings:

- `c` to switch kubernetes context (and select a new namespace in the new context), showing the same pods
  there.
- `n` to switch kubernetes namespace within the same context, showing the same pods there.
- `g` to re-load the pod list
- `l` to show the logs of a pod, with or without follow mode.
- `t` to open a `exec` terminal with a shell to the pod
- `i` to inspect the pod, viewing its YAML source
- `d` to open a TRAMP `dired` buffer for the pod, exploring its file system (and load/save files on it)
- `q` to quit the pod list and return to the deployments buffer

## Viewing a pod's logs

After pressing `l` on a pod, you're presented with some options. They correspond to the same options on
`kubectl log`. After pressing `l` a second time, a new buffer is opened with the pod's logs in it. Logs are
always retrieved asynchronously, and if you choose `-f`, the buffer will keep updating with log messages as
they arrive.

On the log buffer, the following extra key bindings are available:
- `k` to kill the `kuberctl` process that is loading the logs (in case there's too much, or to stop a `-f`)
- `q` to kill the log buffer (and process)
